"""Package each generated GLB as a USDZ with the same mesh for iOS AR Quick Look.

Usage: generate-usdz.py <folder holding the .glb files>
The GLB files come from tools/generate_demo_models.py, the single model source.
"""
from pathlib import Path
import json
import struct
import sys
import zipfile


def read_accessor(glb, model, binary_start, index, code):
    entry = model["accessors"][index]
    view = model["bufferViews"][entry["bufferView"]]
    start = binary_start + view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    components = {"SCALAR": 1, "VEC3": 3}[entry["type"]]
    size = entry["count"] * components * struct.calcsize(code[:1] + code[-1])
    return [row for row in struct.iter_unpack(code, glb[start:start + size])]

def numbers(values):
    return ", ".join(str(v) for v in values)

def point_list(points):
    return ", ".join("(" + numbers(round(v, 7) for v in p) + ")" for p in points)


def convert(source):
    glb = source.read_bytes()
    json_size = struct.unpack_from("<I", glb, 12)[0]
    model = json.loads(glb[20:20 + json_size])
    binary_start = 28 + json_size
    parts = []
    for index, node in enumerate(model["nodes"]):
        mesh = model["meshes"][node["mesh"]]["primitives"][0]
        points = read_accessor(glb, model, binary_start, mesh["attributes"]["POSITION"], "<3f")
        normals = read_accessor(glb, model, binary_start, mesh["attributes"]["NORMAL"], "<3f")
        triangles = read_accessor(glb, model, binary_start, mesh["indices"], "<3H")
        material = mesh["material"]
        color = model["materials"][material]["pbrMetallicRoughness"]["baseColorFactor"][:3]
        assert len(points) == len(normals)
        assert max(i for face in triangles for i in face) < len(points)
        parts.append(f'''
        def Mesh "Part{index}" (prepend apiSchemas = ["MaterialBindingAPI"]) {{
            uniform token subdivisionScheme = "none"
            int[] faceVertexCounts = [{numbers(3 for _ in triangles)}]
            int[] faceVertexIndices = [{numbers(i for face in triangles for i in face)}]
            point3f[] points = [{point_list(points)}]
            normal3f[] normals = [{point_list(normals)}] (interpolation = "vertex")
            double3 xformOp:translate = ({numbers(node.get("translation", [0, 0, 0]))})
            uniform token[] xformOpOrder = ["xformOp:translate"]
            color3f[] primvars:displayColor = [({numbers(color)})]
            rel material:binding = </Product/Materials/Material{material}>
        }}''')

    # AR Quick Look shades from bound materials, so mirror each glTF material.
    looks = []
    for index, entry in enumerate(model["materials"]):
        pbr = entry["pbrMetallicRoughness"]
        looks.append(f'''
            def Material "Material{index}" {{
                token outputs:surface.connect = </Product/Materials/Material{index}/Surface.outputs:surface>
                def Shader "Surface" {{
                    uniform token info:id = "UsdPreviewSurface"
                    color3f inputs:diffuseColor = ({numbers(pbr["baseColorFactor"][:3])})
                    float inputs:roughness = {pbr["roughnessFactor"]}
                    float inputs:metallic = {pbr["metallicFactor"]}
                    token outputs:surface
                }}
            }}''')
    parts.append('    def Scope "Materials" {' + "".join(looks) + '\n    }')
    stage = '#usda 1.0\n(defaultPrim = "Product"\n metersPerUnit = 1\n upAxis = "Y")\n'
    stage += 'def Xform "Product" {\n' + '\n'.join(parts) + '\n}\n'
    entry = zipfile.ZipInfo("Product.usda")
    padding = (-(30 + len(entry.filename) + 4)) % 64
    entry.extra = struct.pack("<HH", 0x1986, padding) + bytes(padding)
    target = source.with_suffix(".usdz")
    with zipfile.ZipFile(target, "w") as archive:
        archive.writestr(entry, stage)
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        assert archive.getinfo(entry.filename).compress_type == zipfile.ZIP_STORED
    raw = target.read_bytes()
    name_size, extra_size = struct.unpack_from("<HH", raw, 26)
    assert (30 + name_size + extra_size) % 64 == 0

    return target


folder = Path(sys.argv[1])
sources = sorted(folder.glob("*.glb"))
assert sources, f"no GLB files in {folder}"
for source in sources:
    print(convert(source).name)
