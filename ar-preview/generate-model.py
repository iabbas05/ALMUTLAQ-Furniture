"""Generate the dimensioned London demonstration asset for mobile preview."""
import json
import math
import struct
from pathlib import Path

# Metres. Product geometry is reconstructed and requires visual approval.
parts = [
    ("Upholstered plinth", (0, .20, 0), (2.10, .34, 1.03), .067, 0),
    ("Back frame", (0, .66, .39), (1.95, .58, .25), .067, 0),
    *[("Rounded arm", (x, .48, -.025), (.24, .53, .96), .085, 0)
      for x in (-.93, .93)],
    *[("Seat cushion", (x, .435, -.15), (.585, .16, .69), .060, 1)
      for x in (-.59, 0, .59)],
    *[("Back cushion", (x, .73, .24), (.583, .54, .22), .088, 1)
      for x in (-.59, 0, .59)],
    *[("Recessed foot", (x, .03, z), (.11, .06, .09), .015, 2)
      for x in (-.86, .86) for z in (-.36, .36)],
]

data = bytearray()
views = []
accessors = []
meshes = []
nodes = []

def accessor(values, code, gl_type, target, low=None, high=None):
    while len(data) % 4:
        data.append(0)
    offset = len(data)
    flattened = [v for row in values for v in row] if gl_type == "VEC3" else values
    data.extend(struct.pack(f"<{len(flattened)}{code}", *flattened))
    views.append(dict(buffer=0, byteOffset=offset, byteLength=len(data)-offset, target=target))
    entry = dict(bufferView=len(views)-1, componentType=5126 if code == "f" else 5123,
                 count=len(values), type=gl_type)
    if low is not None:
        entry.update(min=low, max=high)
    accessors.append(entry)
    return len(accessors)-1

def rounded_box(size, radius):
    halves = [axis / 2 for axis in size]
    inner = [axis - radius for axis in halves]
    positions, normals, triangles = [], [], []
    def samples(axis):
        h, i = halves[axis], inner[axis]
        return [-h, -(h+i)/2, -i, 0, i, (h+i)/2, h]
    for axis in range(3):
        u, v = (axis+1) % 3, (axis+2) % 3
        for sign in (-1, 1):
            start = len(positions)
            for b in samples(v):
                for a in samples(u):
                    raw = [0., 0., 0.]
                    raw[axis], raw[u], raw[v] = sign * halves[axis], a, b
                    centre = [max(-limit, min(value, limit)) for value, limit in zip(raw, inner)]
                    vector = [value-origin for value, origin in zip(raw, centre)]
                    magnitude = math.sqrt(sum(value*value for value in vector))
                    normal = [value/magnitude for value in vector]
                    positions.append([origin + radius*n for origin, n in zip(centre, normal)])
                    normals.append(normal)
            for y in range(6):
                for x in range(6):
                    p = start + 7*y + x
                    faces = [p, p+1, p+8, p, p+8, p+7]
                    if sign < 0:
                        faces = [p, p+8, p+1, p, p+7, p+8]
                    triangles.extend(faces)
    return positions, normals, triangles

world_points = []
for name, centre, size, radius, material in parts:
    points, normals, indices = rounded_box(size, radius)
    world_points.extend([[p[i]+centre[i] for i in range(3)] for p in points])
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    position = accessor(points, "f", "VEC3", 34962, low, high)
    normal = accessor(normals, "f", "VEC3", 34962)
    index = accessor(indices, "H", "SCALAR", 34963)
    meshes.append({"primitives": [dict(attributes={"POSITION": position, "NORMAL": normal},
                                       indices=index, material=material)]})
    nodes.append(dict(name=name, translation=centre, mesh=len(meshes)-1))

bounds = [round(max(p[i] for p in world_points)-min(p[i] for p in world_points), 5) for i in range(3)]
assert bounds == [2.10, 1.00, 1.03], bounds
assert abs(min(p[1] for p in world_points)) < 1e-7
materials = [
    {"name": name, "pbrMetallicRoughness": {"baseColorFactor": color, "metallicFactor": 0,
                                          "roughnessFactor": roughness}}
    for name, color, roughness in [
        ("Warm ivory body", [.73, .69, .62, 1], .93),
        ("Warm ivory cushions", [.83, .79, .71, 1], .96),
        ("Dark recessed feet", [.07, .05, .035, 1], .74),
    ]
]
while len(data) % 4:
    data.append(0)
model = dict(asset={"version": "2.0"}, scene=0, scenes=[{"nodes": list(range(len(nodes)))}],
             nodes=nodes, meshes=meshes, materials=materials, buffers=[{"byteLength": len(data)}],
             bufferViews=views, accessors=accessors)
header = json.dumps(model, separators=(",", ":")).encode()
header += b" " * (-len(header) % 4)
glb = struct.pack("<4sII", b"glTF", 2, 28+len(header)+len(data))
glb += struct.pack("<I4s", len(header), b"JSON") + header
glb += struct.pack("<I4s", len(data), b"BIN\0") + data
Path(__file__).with_name("london-10_14_3.glb").write_bytes(glb)

