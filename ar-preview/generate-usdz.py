"""Package the same dimensioned mesh as a USDZ preview for iOS."""
from pathlib import Path
import json
import struct
import zipfile

folder = Path(__file__).parent
glb = (folder / "london-10_14_3.glb").read_bytes()
json_size = struct.unpack_from("<I", glb, 12)[0]
model = json.loads(glb[20:20 + json_size])
binary_start = 28 + json_size

def read_accessor(index, code):
    entry = model["accessors"][index]
    view = model["bufferViews"][entry["bufferView"]]
    start = binary_start + view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    return [row for row in struct.iter_unpack(code, glb[start:start + view["byteLength"]])]

def numbers(values):
    return ", ".join(str(v) for v in values)

def point_list(points):
    return ", ".join("(" + numbers(round(v, 7) for v in p) + ")" for p in points)

parts = []
for index, node in enumerate(model["nodes"]):
    mesh = model["meshes"][node["mesh"]]["primitives"][0]
    points = read_accessor(mesh["attributes"]["POSITION"], "<3f")
    normals = read_accessor(mesh["attributes"]["NORMAL"], "<3f")
    triangles = read_accessor(mesh["indices"], "<3H")
    color = model["materials"][mesh["material"]]["pbrMetallicRoughness"]["baseColorFactor"][:3]
    assert len(points) == len(normals)
    assert max(i for face in triangles for i in face) < len(points)
    parts.append(f'''
    def Mesh "Part{index}" {{
        uniform token subdivisionScheme = "none"
        int[] faceVertexCounts = [{numbers(3 for _ in triangles)}]
        int[] faceVertexIndices = [{numbers(i for face in triangles for i in face)}]
        point3f[] points = [{point_list(points)}]
        normal3f[] normals = [{point_list(normals)}] (interpolation = "vertex")
        double3 xformOp:translate = ({numbers(node["translation"])})
        uniform token[] xformOpOrder = ["xformOp:translate"]
        color3f[] primvars:displayColor = [({numbers(color)})]
    }}''')
stage = '#usda 1.0\n(defaultPrim = "London"\n metersPerUnit = 1\n upAxis = "Y")\n'
stage += 'def Xform "London" {\n' + '\n'.join(parts) + '\n}\n'
entry = zipfile.ZipInfo("London.usda")
padding = (-(30 + len(entry.filename) + 4)) % 64
entry.extra = struct.pack("<HH", 0x1986, padding) + bytes(padding)
target = folder / "london-10_14_3.usdz"
with zipfile.ZipFile(target, "w") as archive:
    archive.writestr(entry, stage)
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert archive.getinfo(entry.filename).compress_type == zipfile.ZIP_STORED
raw = target.read_bytes()
name_size, extra_size = struct.unpack_from("<HH", raw, 26)
assert (30 + name_size + extra_size) % 64 == 0

