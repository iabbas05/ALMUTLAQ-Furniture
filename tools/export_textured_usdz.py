"""Convert a reviewed, embedded core-PBR GLB draft into a self-contained USDZ.

Requires usd-core. CLI requires the matching Blender audit. No live model is replaced.
Unsupported extensions, animation, external files and UV sets fail explicitly.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import tempfile
import zipfile

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils


class ConversionError(ValueError):
    pass


class Glb:
    def __init__(self, source):
        raw = Path(source).read_bytes()
        if not 28 <= len(raw) <= 200 * 1024 * 1024:
            raise ConversionError('GLB must be between 28 bytes and 200 MB')
        if struct.unpack_from('<4sII', raw) != (b'glTF', 2, len(raw)):
            raise ConversionError('Invalid GLB header')
        chunks, cursor = {}, 12
        while cursor < len(raw):
            if cursor + 8 > len(raw):
                raise ConversionError('Truncated GLB chunk')
            size, kind = struct.unpack_from('<I4s', raw, cursor)
            cursor += 8
            if size % 4 or cursor + size > len(raw) or kind in chunks:
                raise ConversionError('Invalid GLB chunks')
            chunks[kind] = raw[cursor:cursor + size]
            cursor += size
        self.doc = json.loads(chunks[b'JSON'])
        self.binary = chunks[b'BIN\0']
        self.sha256 = hashlib.sha256(raw).hexdigest()
        doc = self.doc
        if doc.get('asset', {}).get('version') != '2.0':
            raise ConversionError('glTF 2.0 is required')
        if doc.get('extensionsRequired') or doc.get('animations') or doc.get('skins'):
            raise ConversionError('Required extensions, animations and skins need another conversion path')
        if len(doc.get('buffers', [])) != 1 or doc['buffers'][0].get('uri'):
            raise ConversionError('Only one embedded GLB buffer is supported')
        if doc['buffers'][0]['byteLength'] > len(self.binary):
            raise ConversionError('Truncated GLB buffer')
        for material in doc.get('materials', []):
            if material.get('extensions'):
                raise ConversionError('Material extensions require explicit conversion support')

    def view(self, index):
        view = self.doc['bufferViews'][index]
        offset, size = view.get('byteOffset', 0), view['byteLength']
        if view.get('buffer', 0) != 0 or offset < 0 or size < 0 or offset + size > len(self.binary):
            raise ConversionError('Buffer view exceeds the embedded buffer')
        return view, self.binary[offset:offset + size]

    def accessor(self, index, expected):
        accessor = self.doc['accessors'][index]
        if accessor['type'] != expected or accessor.get('sparse'):
            raise ConversionError('Unexpected or sparse accessor')
        component = accessor['componentType']
        types = {5121: ('B', 1, 255), 5123: ('H', 2, 65535),
                 5125: ('I', 4, 4294967295), 5126: ('f', 4, 1)}
        if component not in types:
            raise ConversionError('Unsupported accessor component type')
        if expected == 'VEC3' and component != 5126:
            raise ConversionError('Geometry must use floating-point VEC3')
        if expected == 'SCALAR' and component == 5126:
            raise ConversionError('Triangle indices must be unsigned integers')
        code, width, maximum = types[component]
        components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[expected]
        view, data = self.view(accessor['bufferView'])
        count = accessor['count']
        stride, offset = view.get('byteStride', components * width), accessor.get('byteOffset', 0)
        if (not 1 <= count <= 3000000 or offset < 0 or stride < components * width
                or offset + (count - 1) * stride + components * width > len(data)):
            raise ConversionError('Accessor exceeds its buffer')
        values = [struct.unpack_from('<' + code * components, data, offset + n * stride) for n in range(count)]
        if not all(math.isfinite(x) for value in values for x in value):
            raise ConversionError('Non-finite geometry')
        if accessor.get('normalized') and component != 5126:
            values = [tuple(x / maximum for x in value) for value in values]
        return [value[0] for value in values] if components == 1 else values


def convert(source, target, audited_dimensions=None):
    source, target = Path(source).resolve(), Path(target).resolve()
    if target.suffix.lower() != '.usdz' or target.exists():
        raise ConversionError('Choose a new .usdz output path')
    glb = Glb(source)
    doc = glb.doc
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='usdz-review-', dir=target.parent) as work:
        work = Path(work)
        texture_dir = work / 'textures'
        texture_dir.mkdir()
        images = []
        for index, image in enumerate(doc.get('images', [])):
            if image.get('uri') or 'bufferView' not in image:
                raise ConversionError('Only embedded PNG/JPEG textures are supported')
            extension = {'image/png': 'png', 'image/jpeg': 'jpg'}.get(image.get('mimeType'))
            if extension is None:
                raise ConversionError('Decode compressed textures to PNG/JPEG before conversion')
            _, data = glb.view(image['bufferView'])
            path = texture_dir / f'image_{index}.{extension}'
            path.write_bytes(data)
            images.append('textures/' + path.name)
        stage = Usd.Stage.CreateNew(str(work / 'product.usdc'))
        product = UsdGeom.Xform.Define(stage, '/Product')
        stage.SetDefaultPrim(product.GetPrim())
        UsdGeom.SetStageMetersPerUnit(stage, 1)
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        materials = []

        for index, entry in enumerate(doc.get('materials', []) or [{}]):
            path = f'/Product/Materials/Material_{index}'
            material = UsdShade.Material.Define(stage, path)
            shader = UsdShade.Shader.Define(stage, path + '/Surface')
            shader.CreateIdAttr('UsdPreviewSurface')
            shader.CreateOutput('surface', Sdf.ValueTypeNames.Token)
            material.CreateSurfaceOutput().ConnectToSource(shader.GetOutput('surface'))
            reader = UsdShade.Shader.Define(stage, path + '/UV')
            reader.CreateIdAttr('UsdPrimvarReader_float2')
            reader.CreateInput('varname', Sdf.ValueTypeNames.Token).Set('st')
            reader.CreateOutput('result', Sdf.ValueTypeNames.Float2)

            def texture(label, info, colorspace, scale=(1, 1, 1, 1), bias=(0, 0, 0, 0)):
                if info.get('texCoord', 0) != 0 or info.get('extensions'):
                    raise ConversionError('Only untransformed TEXCOORD_0 textures are supported')
                tex = doc['textures'][info['index']]
                if tex.get('extensions'):
                    raise ConversionError('Texture extensions need decoding before USD conversion')
                node = UsdShade.Shader.Define(stage, path + '/' + label)
                node.CreateIdAttr('UsdUVTexture')
                node.CreateInput('file', Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath(images[tex['source']]))
                node.CreateInput('sourceColorSpace', Sdf.ValueTypeNames.Token).Set(colorspace)
                node.CreateInput('st', Sdf.ValueTypeNames.Float2).ConnectToSource(reader.GetOutput('result'))
                node.CreateInput('scale', Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(*scale))
                node.CreateInput('bias', Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(*bias))
                sampler = doc.get('samplers', [])[tex['sampler']] if 'sampler' in tex else {}
                for axis in ('S', 'T'):
                    mode = {10497: 'repeat', 33071: 'clamp', 33648: 'mirror'}.get(sampler.get('wrap' + axis, 10497))
                    if mode is None:
                        raise ConversionError('Unsupported texture wrap mode')
                    node.CreateInput('wrap' + axis, Sdf.ValueTypeNames.Token).Set(mode)
                for channel in ('r', 'g', 'b', 'a', 'rgb'):
                    node.CreateOutput(channel, Sdf.ValueTypeNames.Float3 if channel == 'rgb' else Sdf.ValueTypeNames.Float)
                return node

            pbr = entry.get('pbrMetallicRoughness', {})
            color = pbr.get('baseColorFactor', [1, 1, 1, 1])
            alpha_mode = entry.get('alphaMode', 'OPAQUE')
            if alpha_mode not in ('OPAQUE', 'MASK', 'BLEND'):
                raise ConversionError('Invalid alpha mode')
            base = shader.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f)
            opacity = shader.CreateInput('opacity', Sdf.ValueTypeNames.Float)
            if 'baseColorTexture' in pbr:
                node = texture('BaseColor', pbr['baseColorTexture'], 'sRGB', color)
                base.ConnectToSource(node.GetOutput('rgb'))
                if alpha_mode != 'OPAQUE':
                    opacity.ConnectToSource(node.GetOutput('a'))
                else:
                    opacity.Set(1)
            else:
                base.Set(Gf.Vec3f(*color[:3]))
                opacity.Set(color[3] if alpha_mode != 'OPAQUE' else 1)
            if alpha_mode == 'MASK':
                shader.CreateInput('opacityThreshold', Sdf.ValueTypeNames.Float).Set(entry.get('alphaCutoff', .5))
            roughness = shader.CreateInput('roughness', Sdf.ValueTypeNames.Float)
            metallic = shader.CreateInput('metallic', Sdf.ValueTypeNames.Float)
            rf, mf = pbr.get('roughnessFactor', 1), pbr.get('metallicFactor', 1)
            if 'metallicRoughnessTexture' in pbr:
                node = texture('MetalRough', pbr['metallicRoughnessTexture'], 'raw', (1, rf, mf, 1))
                roughness.ConnectToSource(node.GetOutput('g'))
                metallic.ConnectToSource(node.GetOutput('b'))
            else:
                roughness.Set(rf)
                metallic.Set(mf)
            if 'normalTexture' in entry:
                info = entry['normalTexture']
                strength = info.get('scale', 1)
                node = texture('Normal', info, 'raw', (2 * strength, 2 * strength, 2, 1), (-strength, -strength, -1, 0))
                shader.CreateInput('normal', Sdf.ValueTypeNames.Normal3f).ConnectToSource(node.GetOutput('rgb'))
            if 'occlusionTexture' in entry:
                info = entry['occlusionTexture']
                strength = info.get('strength', 1)
                node = texture('Occlusion', info, 'raw', (strength, 1, 1, 1), (1 - strength, 0, 0, 0))
                shader.CreateInput('occlusion', Sdf.ValueTypeNames.Float).ConnectToSource(node.GetOutput('r'))
            emission = entry.get('emissiveFactor', [0, 0, 0])
            emit = shader.CreateInput('emissiveColor', Sdf.ValueTypeNames.Color3f)
            if 'emissiveTexture' in entry:
                node = texture('Emissive', entry['emissiveTexture'], 'sRGB', (*emission, 1))
                emit.ConnectToSource(node.GetOutput('rgb'))
            else:
                emit.Set(Gf.Vec3f(*emission))
            materials.append(material)

        mesh_count = 0

        def visit(index, parent, lineage):
            nonlocal mesh_count
            if index in lineage or len(lineage) > 64:
                raise ConversionError('Cyclic or excessive node hierarchy')
            node = doc['nodes'][index]
            path = parent + '/Node_' + str(index)
            xform = UsdGeom.Xform.Define(stage, path)
            if 'matrix' in node:
                matrix = node['matrix']
                if len(matrix) != 16 or not all(math.isfinite(n) for n in matrix):
                    raise ConversionError('Invalid node matrix')
                # glTF column-major becomes Gf's row-vector matrix directly.
                xform.AddTransformOp().Set(Gf.Matrix4d(*matrix))
            else:
                xform.AddTranslateOp().Set(Gf.Vec3d(*node.get('translation', [0, 0, 0])))
                q = node.get('rotation', [0, 0, 0, 1])
                xform.AddOrientOp().Set(Gf.Quatf(q[3], Gf.Vec3f(*q[:3])))
                xform.AddScaleOp().Set(Gf.Vec3f(*node.get('scale', [1, 1, 1])))
            if 'mesh' in node:
                for number, primitive in enumerate(doc['meshes'][node['mesh']]['primitives']):
                    if primitive.get('mode', 4) != 4 or primitive.get('targets') or primitive.get('extensions'):
                        raise ConversionError('Only uncompressed static triangle primitives are supported')
                    attributes = primitive['attributes']
                    points = glb.accessor(attributes['POSITION'], 'VEC3')
                    indices = glb.accessor(primitive['indices'], 'SCALAR') if 'indices' in primitive else list(range(len(points)))
                    if len(indices) % 3 or any(n < 0 or n >= len(points) for n in indices):
                        raise ConversionError('Invalid triangle indices')
                    mesh = UsdGeom.Mesh.Define(stage, path + '/Mesh_' + str(number))
                    mesh.CreateSubdivisionSchemeAttr('none')
                    mesh.CreatePointsAttr(points)
                    mesh.CreateFaceVertexCountsAttr([3] * (len(indices) // 3))
                    mesh.CreateFaceVertexIndicesAttr(indices)
                    mesh.CreateExtentAttr([tuple(min(p[i] for p in points) for i in range(3)),
                                           tuple(max(p[i] for p in points) for i in range(3))])
                    if 'NORMAL' in attributes:
                        normals = glb.accessor(attributes['NORMAL'], 'VEC3')
                        if len(normals) != len(points):
                            raise ConversionError('Normals and positions differ in length')
                        mesh.CreateNormalsAttr(normals)
                        mesh.SetNormalsInterpolation('vertex')
                    mat_index = primitive.get('material')
                    if mat_index is None:
                        mat_index = len(materials)
                        # An unmaterialed mesh must not inherit another product material.
                        default = UsdShade.Material.Define(stage, '/Product/Materials/Default')
                        default_shader = UsdShade.Shader.Define(stage, '/Product/Materials/Default/Surface')
                        default_shader.CreateIdAttr('UsdPreviewSurface')
                        default_shader.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(1))
                        default_shader.CreateOutput('surface', Sdf.ValueTypeNames.Token)
                        default.CreateSurfaceOutput().ConnectToSource(default_shader.GetOutput('surface'))
                        material = default
                        entry = {}
                    else:
                        material, entry = materials[mat_index], doc['materials'][mat_index]
                    uses_texture = any(k in entry for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture')) or any(
                        k in entry.get('pbrMetallicRoughness', {}) for k in ('baseColorTexture', 'metallicRoughnessTexture'))
                    if 'TEXCOORD_0' in attributes:
                        uv = glb.accessor(attributes['TEXCOORD_0'], 'VEC2')
                        if len(uv) != len(points):
                            raise ConversionError('UV and position counts differ')
                        UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, 'vertex').Set(
                            [(u, 1 - v) for u, v in uv])
                    elif uses_texture:
                        raise ConversionError('Textured mesh has no TEXCOORD_0')
                    mesh.CreateDoubleSidedAttr(entry.get('doubleSided', False))
                    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)
                    mesh_count += 1
            for child in node.get('children', []):
                visit(child, path, lineage | {index})

        for node in doc['scenes'][doc.get('scene', 0)]['nodes']:
            visit(node, '/Product', set())
        if mesh_count == 0:
            raise ConversionError('No mesh in the selected GLB scene')
        stage.GetRootLayer().Save()
        box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ['default']).ComputeWorldBound(product.GetPrim()).ComputeAlignedRange()
        dimensions = list(box.GetSize())
        if not all(math.isfinite(n) and n > 0 for n in dimensions):
            raise ConversionError('Invalid converted model bounds')
        if audited_dimensions is not None:
            if any(abs(a - b) > .00001 for a, b in zip(dimensions, audited_dimensions)) or abs(box.GetMin()[1]) > .00001:
                raise ConversionError('USD dimensions or floor contact differ from the reviewed GLB')
        pending = work / 'product.usdz'
        if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(work / 'product.usdc')), str(pending)):
            raise ConversionError('USDZ packaging failed')
        if not Usd.Stage.Open(str(pending)):
            raise ConversionError('Packaged USDZ does not reopen')
        if target.exists():
            raise ConversionError('Output appeared during conversion; preserving it')
        with zipfile.ZipFile(pending) as archive:
            embedded_images = sum(Path(name).suffix.lower() in ('.png', '.jpg', '.jpeg') for name in archive.namelist())
        pending.replace(target)
    return {'sourceSha256': glb.sha256, 'usdzSha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'dimensionsYUp': dimensions, 'meshCount': mesh_count, 'embeddedImages': embedded_images,
            'status': 'draft_requires_visual_and_device_review', 'deviceTested': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--audit', required=True, type=Path)
    args = parser.parse_args()
    audit = json.loads(args.audit.read_text())
    if hashlib.sha256(args.input.read_bytes()).hexdigest() != audit.get('glbSha256'):
        parser.error('Audit hash does not match the GLB')
    measured = audit['actualDimensions']
    report = convert(args.input, args.output, [measured['width'], measured['height'], measured['depth']])
    report['sku'] = audit['sku']
    report['dimensionCheckPassed'] = audit.get('withinFiveMillimetres') is True
    args.output.with_suffix('.usdz.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('USDZ_DRAFT_READY ' + str(args.output))


if __name__ == '__main__':
    main()
