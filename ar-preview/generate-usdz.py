from pathlib import Path
import json
import struct
import zipfile

folder = Path(__file__).parent
glb = (folder / "london-10_14_3.glb").read_bytes()
json_size = struct.unpack_from("<I", glb, 12)[0]
nodes = json.loads(glb[20:20 + json_size])["nodes"]
parts = []
for index, node in enumerate(nodes):
    position = tuple(node["translation"])
    size = tuple(node["scale"])
    parts.append(f'''
    def Cube "Part{index}" {{
        double size = 1
        double3 xformOp:translate = {position}
        double3 xformOp:scale = {size}
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]
        color3f[] primvars:displayColor = [(0.86, 0.81, 0.72)]
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
