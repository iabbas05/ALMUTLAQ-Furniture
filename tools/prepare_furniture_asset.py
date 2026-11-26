"""Run with Blender: import a draft GLB, audit its scale, and render review views.

blender -b --python tools/prepare_furniture_asset.py -- --input model.glb
    --output builds/asset-review/SKU --sku SKU --width 2.1 --depth 1.03 --height 1

Optional --fit-width applies ONE uniform scale, preserving the generated shape.
This never publishes or replaces catalogue assets and never claims visual approval.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def bounds(objects):
    points = [o.matrix_world @ Vector(corner) for o in objects for corner in o.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return low, high


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sku', required=True)
    for dimension in ('width', 'depth', 'height'):
        parser.add_argument('--' + dimension, type=float, required=True)
    parser.add_argument('--fit-width', action='store_true')
    parser.add_argument('--no-renders', action='store_true', help='Audit/export only, for automated checks')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    expected = (args.width, args.depth, args.height)
    if any(not math.isfinite(n) or n <= 0 for n in expected):
        parser.error('Expected dimensions must be positive finite metres')
    source = args.input.resolve(strict=True)
    output = args.output.resolve()
    if source.suffix.lower() != '.glb':
        parser.error('Input must be a GLB')
    # Draft files stay self-contained. Do not fetch external textures/buffers.
    raw = source.read_bytes()
    import struct
    if len(raw) < 20 or raw[:4] != b'glTF':
        parser.error('Invalid GLB header')
    size, kind = struct.unpack_from('<I4s', raw, 12)
    if kind != b'JSON' or size > len(raw) - 20:
        parser.error('Invalid GLB JSON chunk')
    document = json.loads(raw[20:20 + size])
    for item in document.get('buffers', []) + document.get('images', []):
        if item.get('uri') and not item['uri'].startswith('data:'):
            parser.error('External buffers or textures are not accepted')
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.ops.import_scene.gltf(filepath=str(source))
    objects = list(bpy.context.scene.objects)
    meshes = [o for o in objects if o.type == 'MESH']
    if not meshes:
        parser.error('Input contains no mesh')
    if document.get('animations') or document.get('skins'):
        parser.error('Furniture review accepts static models only')
    low, high = bounds(meshes)
    original = high - low
    if any(not math.isfinite(n) or n <= 0 for n in original):
        parser.error('Invalid or flat mesh bounds')
    factor = args.width / original.x if args.fit_width else 1.0
    # Transform top-level objects only, so child meshes are never scaled twice.
    pivot = bpy.data.objects.new('Product metre transform', None)
    bpy.context.collection.objects.link(pivot)
    for obj in objects:
        if obj.parent is None:
            obj.parent = pivot
    pivot.scale = (factor,) * 3
    bpy.context.view_layer.update()
    low, high = bounds(meshes)
    pivot.location = Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
    bpy.context.view_layer.update()
    low, high = bounds(meshes)
    actual = tuple(high - low)
    errors = tuple(a - e for a, e in zip(actual, expected))
    triangles = sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in meshes)
    materials = {m for obj in meshes for m in obj.data.materials if m is not None}
    images = [image for image in bpy.data.images if image.source == 'FILE' and image.users > 0]
    for image in images:
        # GLB import already embeds its image bytes. Repacking a lazy-loaded
        # embedded image can discard that packed source on some Blender builds.
        if image.packed_file is None:
            image.pack()
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    pivot.select_set(True)
    for obj in objects:
        obj.select_set(True)
    target = output / 'product.glb'
    if target == source:
        parser.error('Output must differ from the source asset')
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB',
                              use_selection=True, export_animations=False, export_yup=True)
    exported = target.read_bytes()
    exported_json_size = struct.unpack_from('<I', exported, 12)[0]
    exported_document = json.loads(exported[20:20 + exported_json_size])
    if document.get('textures') and not exported_document.get('textures'):
        raise RuntimeError('Texture round trip failed. This draft is not ready for review.')
    audit = {
        'schemaVersion': 1, 'sku': args.sku, 'unit': 'm',
        'status': 'draft_requires_visual_approval',
        'blenderVersion': bpy.app.version_string,
        'sourceSha256': hashlib.sha256(raw).hexdigest(),
        'glbSha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        'expectedDimensions': dict(zip(('width', 'depth', 'height'), expected)),
        'actualDimensions': dict(zip(('width', 'depth', 'height'), actual)),
        'dimensionErrorsMetres': dict(zip(('width', 'depth', 'height'), errors)),
        'withinFiveMillimetres': all(abs(e) <= .005 for e in errors),
        'uniformScaleApplied': factor, 'triangleCount': triangles,
        'materialCount': len(materials),
        'embeddedTextureCount': len(exported_document.get('images', [])),
        'sourceExtensionsRequired': document.get('extensionsRequired', []),
        'deviceTested': False,
    }
    (output / 'audit.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    # Save editable product before adding review-only camera, floor and lights.
    bpy.ops.wm.save_as_mainfile(filepath=str(output / 'product.blend'))
    if args.no_renders:
        print('ASSET_DRAFT_PREPARED ' + str(output), flush=True)
        return
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world = bpy.data.worlds.new('Review world')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.32, .32, .32, 1)
    scene.view_settings.view_transform = 'Standard'
    span = max(actual)
    for name, location, energy, size in [
        ('Key', (-span, -span, span * 2), 800, span * 2),
        ('Fill', (span, -span / 2, span), 500, span * 1.5),
        ('Back', (0, span, span * 2), 600, span * 1.5),
    ]:
        lamp = bpy.data.lights.new(name, 'AREA')
        lamp.energy, lamp.shape, lamp.size = energy, 'DISK', size
        obj = bpy.data.objects.new(name, lamp)
        bpy.context.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((0, 0, actual[2] / 2)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    camera = bpy.data.objects.new('Review camera', bpy.data.cameras.new('Review camera'))
    bpy.context.collection.objects.link(camera)
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = span * 1.6
    scene.camera = camera
    for label, direction in [('front', (0, -1, .4)), ('side', (1, 0, .35)), ('back', (0, 1, .4))]:
        focus = Vector((0, 0, actual[2] / 2))
        camera.location = focus + Vector(direction).normalized() * span * 3
        camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(output / (label + '.png'))
        bpy.ops.render.render(write_still=True)
    print('ASSET_REVIEW_READY ' + str(output), flush=True)


if __name__ == '__main__':
    main()
