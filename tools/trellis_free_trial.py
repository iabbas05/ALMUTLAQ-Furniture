"""One opt-in TRELLIS.2 trial on the official public Hugging Face Space.

Uses its Gradio queue, not paid inference. Stops on quota/authentication errors.
HF_TOKEN is optional and read only from the environment, never a CLI argument.
Input is uploaded to the external service. Output remains an unapproved draft.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = 'https://microsoft-trellis-2.hf.space'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sku', required=True)
    parser.add_argument('--resolution', choices=['512', '1024', '1536'], default='1024')
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    if not 0 <= args.seed <= 2147483647:
        parser.error('Seed must be between 0 and 2147483647')
    if not re.fullmatch(r'[A-Za-z0-9_]+', args.sku):
        parser.error('SKU must contain letters, numbers or underscores')
    source = args.input.resolve(strict=True)
    if source.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp'):
        parser.error('Use a PNG, JPEG or WebP reference photo')
    photo = source.read_bytes()
    if not 100 <= len(photo) <= 20 * 1024 * 1024:
        parser.error('Image must be between 100 bytes and 20 MB')
    args.output.mkdir(parents=True, exist_ok=True)
    if (args.output / 'product-draft.glb').exists():
        parser.error('Choose a fresh output directory to preserve the previous draft')
    headers = {}
    if os.environ.get('HF_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['HF_TOKEN']
    session = uuid.uuid4().hex

    def request(path, data=None, content_type=None, timeout=45, authenticate=True):
        outgoing = dict(headers) if authenticate else {}
        if content_type:
            outgoing['Content-Type'] = content_type
        req = urllib.request.Request(BASE + path, data=data, headers=outgoing)
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as error:
            # Headers and tokens never enter logs.
            raise RuntimeError('Service HTTP ' + str(error.code) + ': ' + error.read(2000).decode(errors='replace')) from None

    with request('/config') as response:
        config = json.load(response)
    functions = {row['api_name']: row['id'] for row in config['dependencies'] if row.get('api_name')}
    for name in ('start_session', 'preprocess_image', 'image_to_3d', 'extract_glb'):
        if name not in functions:
            raise RuntimeError('Space API changed: missing ' + name)
    audit = {'sku': args.sku, 'status': 'trial_started', 'provider': BASE,
             'sourceSha256': hashlib.sha256(photo).hexdigest(),
             'resolution': args.resolution, 'seed': args.seed, 'deviceTested': False}

    def save():
        (args.output / 'trial.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')

    def call(name, data):
        payload = json.dumps({'data': data, 'fn_index': functions[name], 'session_hash': session}).encode()
        with request('/gradio_api/queue/join', payload, 'application/json') as response:
            event_id = json.load(response)['event_id']
        print(name + ': queued', flush=True)
        # Submission is never repeated after an uncertain result or timeout.
        with request('/gradio_api/queue/data?session_hash=' + session, timeout=180) as response:
            for raw in response:
                line = raw.decode().strip()
                if not line.startswith('data:'):
                    continue
                message = json.loads(line[5:])
                if message.get('event_id') != event_id:
                    continue
                if message.get('msg') == 'process_completed':
                    result = message.get('output', {})
                    if not message.get('success') or result.get('error'):
                        raise RuntimeError(str(result.get('error', 'Space task failed')))
                    print(name + ': completed', flush=True)
                    return result['data']
        raise RuntimeError('Stream ended without completion; do not assume a model was generated')

    save()
    try:
        call('start_session', [])
        boundary = 'AlmutlaqAsset' + uuid.uuid4().hex
        filename = 'reference' + source.suffix.lower()
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="files"; filename="{filename}"\r\n'
                'Content-Type: application/octet-stream\r\n\r\n').encode()
        body += photo + f'\r\n--{boundary}--\r\n'.encode()
        with request('/gradio_api/upload', body, 'multipart/form-data; boundary=' + boundary) as response:
            uploaded = json.load(response)[0]
        processed = call('preprocess_image', [{'path': uploaded, 'meta': {'_type': 'gradio.FileData'}}])[0]
        call('image_to_3d', [processed, args.seed, args.resolution,
                           7.5, .7, 12, 5., 7.5, .5, 12, 3., 1., 0., 12, 3.])
        exported = call('extract_glb', [None, 100000, 2048])
        file = exported[0]
        path = file.get('path') if isinstance(file, dict) else file
        url = file.get('url') if isinstance(file, dict) else None
        if url:
            if urllib.parse.urlsplit(url).netloc != urllib.parse.urlsplit(BASE).netloc:
                raise RuntimeError('Unexpected model download host')
            download_path = url[len(BASE):]
        elif isinstance(path, str):
            download_path = '/gradio_api/file=' + urllib.parse.quote(path, safe='/')
        else:
            raise RuntimeError('Missing GLB result')
        with request(download_path, timeout=120, authenticate=False) as response:
            model = response.read(200 * 1024 * 1024 + 1)
        if model[:4] != b'glTF' or len(model) > 200 * 1024 * 1024:
            raise RuntimeError('Result is not an accepted GLB')
        (args.output / 'product-draft.glb').write_bytes(model)
        audit.update(status='draft_requires_geometry_and_visual_review',
                     glbSha256=hashlib.sha256(model).hexdigest(), bytes=len(model))
        save()
        print('DRAFT_GLB_READY ' + str(args.output / 'product-draft.glb'), flush=True)
    except Exception as error:
        audit.update(status='stopped_no_approved_model', error=str(error)[:2000])
        save()
        raise SystemExit(str(error)) from None


if __name__ == '__main__':
    main()
