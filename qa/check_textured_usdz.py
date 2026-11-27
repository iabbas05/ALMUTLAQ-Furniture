"""Open real USDZ outputs and inspect packaged image bytes, UVs and PBR wiring."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

from pxr import Sdf, Usd, UsdGeom, UsdShade

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from export_textured_usdz import ConversionError, Glb, convert

FOLDER = ROOT / 'build' / 'asset-review-check'
SOURCE = FOLDER / 'correct-scale' / 'product.glb'
if not SOURCE.exists():
    raise SystemExit('Run python qa/check_asset_review.py first')
OUTPUT = FOLDER / 'usdz'
OUTPUT.mkdir(parents=True, exist_ok=True)
source = Glb(SOURCE)


def write_glb(path, document):
    encoded = json.dumps(document, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    binary = source.binary
    binary += b'\0' * (-len(binary) % 4)
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(encoded) + len(binary))
                     + struct.pack('<I4s', len(encoded), b'JSON') + encoded
                     + struct.pack('<I4s', len(binary), b'BIN\0') + binary)


def fresh(name):
    path = OUTPUT / name
    if path.exists():
        path.unlink()  # Synthetic test artifacts only.
    return path


document = copy.deepcopy(source.doc)
material = document['materials'][0]
material['pbrMetallicRoughness']['roughnessFactor'] = .6
material['pbrMetallicRoughness']['metallicFactor'] = .2
material['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': 0}
material['normalTexture'] = {'index': 0, 'scale': .75}
material['occlusionTexture'] = {'index': 0, 'strength': .8}
pbr_source = OUTPUT / 'pbr.glb'
write_glb(pbr_source, document)
target = fresh('pbr.usdz')
report = convert(pbr_source, target, [2, 1, 1])
assert report['embeddedImages'] == 1 and report['deviceTested'] is False
stage = Usd.Stage.Open(str(target))
assert UsdGeom.GetStageMetersPerUnit(stage) == 1
assert UsdGeom.GetStageUpAxis(stage) == 'Y'
meshes = [UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
assert meshes and UsdShade.MaterialBindingAPI(meshes[0]).ComputeBoundMaterial()[0]
primvars = UsdGeom.PrimvarsAPI(meshes[0]).GetPrimvar('st').Get()
original_primitive = document['meshes'][0]['primitives'][0]
uv = source.accessor(original_primitive['attributes']['TEXCOORD_0'], 'VEC2')
assert all(abs(a[0] - b[0]) < 1e-6 and abs(a[1] - (1 - b[1])) < 1e-6 for a, b in zip(primvars, uv))
surface = UsdShade.Shader.Get(stage, '/Product/Materials/Material_0/Surface')
for input_name, expected_channel in [('roughness', 'g'), ('metallic', 'b'), ('normal', 'rgb'), ('occlusion', 'r')]:
    assert str(surface.GetInput(input_name).GetConnectedSource()[1]) == expected_channel
for name, colorspace in [('BaseColor', 'sRGB'), ('MetalRough', 'raw'), ('Normal', 'raw'), ('Occlusion', 'raw')]:
    shader = UsdShade.Shader.Get(stage, '/Product/Materials/Material_0/' + name)
    assert shader.GetInput('sourceColorSpace').Get() == colorspace
assert list(UsdShade.Shader.Get(stage, '/Product/Materials/Material_0/Normal').GetInput('scale').Get()) == [1.5, 1.5, 2, 1]
image_bytes = source.view(document['images'][0]['bufferView'])[1]
with zipfile.ZipFile(target) as archive:
    images = [name for name in archive.namelist() if name.endswith('.png')]
    assert len(images) == 1
    assert hashlib.sha256(archive.read(images[0])).digest() == hashlib.sha256(image_bytes).digest()
    for info in archive.infolist():
        assert info.compress_type == zipfile.ZIP_STORED
        with target.open('rb') as package:
            package.seek(info.header_offset + 26)
            name_size, extra_size = struct.unpack('<HH', package.read(4))
            assert (info.header_offset + 30 + name_size + extra_size) % 64 == 0

# A parent glTF column-major matrix must preserve rotation and translation in USD.
rotated = copy.deepcopy(source.doc)
roots = rotated['scenes'][rotated.get('scene', 0)]['nodes']
rotated['nodes'].append({'children': roots, 'matrix': [0, 0, -1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 4, 0, 3, 1]})
rotated['scenes'][rotated.get('scene', 0)]['nodes'] = [len(rotated['nodes']) - 1]
rotated_source = OUTPUT / 'rotated.glb'
write_glb(rotated_source, rotated)
rotated_target = fresh('rotated.usdz')
convert(rotated_source, rotated_target)
rotated_stage = Usd.Stage.Open(str(rotated_target))
box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ['default']).ComputeWorldBound(rotated_stage.GetDefaultPrim()).ComputeAlignedRange()
assert all(abs(a - b) < 1e-6 for a, b in zip(box.GetSize(), [1, 1, 2]))
assert all(abs(a - b) < 1e-6 for a, b in zip(box.GetMidpoint(), [4, .5, 3]))

for label, mutate in [
    ('required-extension', lambda d: d.update(extensionsRequired=['TEST_unsupported'])),
    ('external-image', lambda d: d['images'][0].update(uri='https://example.com/not-fetched.png')),
    ('missing-uv', lambda d: d['meshes'][0]['primitives'][0]['attributes'].pop('TEXCOORD_0')),
]:
    invalid = copy.deepcopy(document)
    mutate(invalid)
    path = OUTPUT / (label + '.glb')
    write_glb(path, invalid)
    output = fresh(label + '.usdz')
    try:
        convert(path, output)
    except ConversionError:
        assert not output.exists()
    else:
        raise AssertionError('Unsupported asset accepted: ' + label)
try:
    convert(pbr_source, target)
except ConversionError:
    pass
else:
    raise AssertionError('Existing draft was overwritten')
print('TEXTURED_USDZ_CHECK_PASSED: image bytes, UVs, PBR channels, matrices, metre scale, package alignment and refusal boundaries')
