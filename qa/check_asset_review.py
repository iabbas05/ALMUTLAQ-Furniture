"""Real Blender integration check using a synthetic textured box, not furniture."""
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'build' / 'asset-review-check'
OUTPUT.mkdir(parents=True, exist_ok=True)
BLENDER = os.environ.get('BLENDER') or shutil.which('blender')
if not BLENDER:
    raise SystemExit('Blender is required for this integration check')


def run(*args):
    result = subprocess.run([BLENDER, '-b', '--python-exit-code', '1', *args],
                            cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout[-6000:] + result.stderr[-2000:])


fixture = OUTPUT / 'fixture.glb'
setup = OUTPUT / 'make_fixture.py'
setup.write_text('''import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1)
cube = bpy.context.object
cube.scale = (1, .5, .5)
material = bpy.data.materials.new('TEST checker')
material.use_nodes = True
texture = material.node_tree.nodes.new('ShaderNodeTexImage')
image = bpy.data.images.new('TEST embedded pixels', 2, 2)
image.pixels = [1,0,0,1, 0,1,0,1, 0,0,1,1, 1,1,1,1]
image.pack()
texture.image = image
material.node_tree.links.new(texture.outputs['Color'], material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
cube.data.materials.append(material)
bpy.ops.export_scene.gltf(filepath=OUTPUT_PATH, export_format='GLB')
'''.replace('OUTPUT_PATH', repr(str(fixture))), encoding='utf-8')
run('--python', str(setup))

for name, depth, expected_pass in [('correct-scale', 1, True), ('wrong-depth', 1.5, False)]:
    target = OUTPUT / name
    run('--python', str(ROOT / 'tools/prepare_furniture_asset.py'), '--',
        '--input', str(fixture), '--output', str(target), '--sku', 'TEST_TEXTURED_BOX',
        '--width', '2', '--depth', str(depth), '--height', '1', '--fit-width', '--no-renders')
    report = json.loads((target / 'audit.json').read_text())
    assert report['withinFiveMillimetres'] is expected_pass, report
    assert abs(report['uniformScaleApplied'] - 2) < 1e-6
    assert abs(report['actualDimensions']['depth'] - 1) < 1e-6
    assert report['embeddedTextureCount'] >= 1
    assert report['deviceTested'] is False
    assert report['status'] == 'draft_requires_visual_approval'
    assert (target / 'product.blend').stat().st_size > 0
    raw = (target / 'product.glb').read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + size])
    assert document['images'] and all('bufferView' in image for image in document['images'])
    assert any('baseColorTexture' in mat.get('pbrMetallicRoughness', {}) for mat in document['materials'])
print('ASSET_REVIEW_CHECK_PASSED: embedded texture preserved; uniform metre scale; wrong depth stays unapproved')
