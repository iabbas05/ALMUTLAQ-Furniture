"""Reconstructed London demo meshes. Dimensions verified against product pages.
These assets need visual approval. They are not a scan or manufacturer CAD.
Outputs GLB for mobile/web and the same triangles in a small Unity demo format.
"""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

def rounded_box(size, radius):
    halves = [a / 2 for a in size]
    radius = min(radius, min(halves) * .95)
    inner = [a - radius for a in halves]
    positions, normals, indices = [], [], []
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
                    centre = [max(-limit, min(n, limit)) for n, limit in zip(raw, inner)]
                    vec = [n-origin for n, origin in zip(raw, centre)]
                    length = math.sqrt(sum(n*n for n in vec))
                    normal = [n/length for n in vec]
                    positions.append([origin + radius*n for origin, n in zip(centre, normal)])
                    normals.append(normal)
            for y in range(6):
                for x in range(6):
                    p = start + 7*y + x
                    indices.extend([p, p+1, p+8, p, p+8, p+7] if sign > 0
                                   else [p, p+8, p+1, p, p+7, p+8])
    return positions, normals, indices

def parts(width, depth, height, seats, style="london"):
    if style == "square":
        return square_parts(width, depth, height, seats)
    arm = .24 if seats == 3 else .14
    inside = width - 2*arm
    seat_width = inside/seats
    parts = [
        ("Upholstered base", (0, .20, 0), (width, .34, depth), .067, 0),
        ("Back frame", (0, height-.31, depth/2-.125), (width-.10, .50, .25), .067, 0),
        *[("Rounded arm", (x, .47, -.025), (arm, .52, depth-.06), .075, 0)
          for x in (-(width-arm)/2, (width-arm)/2)],
        *[("Seat cushion", (-inside/2 + seat_width*(i+.5), .44, -.12),
           (seat_width-.012, .16, depth-.34), .055, 1) for i in range(seats)],
        *[("Back cushion", (-inside/2 + seat_width*(i+.5), height-.27, depth/2-.26),
           (seat_width-.018, .54, .23), .075, 1) for i in range(seats)],
        *[("Recessed foot", (x, .03, z), (.085, .06, .085), .012, 2)
          for x in (-width/2+.16, width/2-.16) for z in (-depth/2+.15, depth/2-.15)],
    ]
    return parts

def square_parts(width, depth, height, seats):
    """Low square-arm sofa on visible wooden legs (CityW Warm Beige style)."""
    arm, legs = .17, .10
    inside = width - 2*arm
    seat_width = inside/seats
    return [
        ("Upholstered base", (0, legs + .14, 0), (width, .28, depth), .02, 0),
        ("Back frame", (0, (legs + height)/2 + .06, depth/2-.09), (width, height - legs - .12, .18), .02, 0),
        *[("Square arm", (x, legs + (height - .16 - legs)/2, -.0), (arm, height - .16 - legs, depth), .02, 0)
          for x in (-(width-arm)/2, (width-arm)/2)],
        *[("Seat cushion", (-inside/2 + seat_width*(i+.5), legs + .34, -.08),
           (seat_width-.012, .12, depth-.34), .03, 1) for i in range(seats)],
        *[("Back cushion", (-inside/2 + seat_width*(i+.5), height-.20, depth/2-.27),
           (seat_width-.018, .40, .20), .05, 1) for i in range(seats)],
        *[("Wooden leg", (x, legs/2, z), (.05, legs, .05), .006, 2)
          for x in (-width/2+.08, width/2-.08) for z in (-depth/2+.08, depth/2-.08)],
    ]

PALETTES = {
    "london": [
        ("Ivory body", [.73, .69, .62, 1], .93),
        ("Ivory cushions", [.83, .79, .71, 1], .96),
        ("Recessed feet", [.07, .05, .035, 1], .74),
    ],
    "warm-beige": [
        ("Warm beige woven body", [.50, .40, .29, 1], .95),
        ("Warm beige woven cushions", [.58, .47, .35, 1], .97),
        ("Solid wood legs", [.22, .12, .06, 1], .62),
    ],
}

def build(output, stem, width, depth, height, seats, style="london", palette="london", sku=None):
    materials_in_use = PALETTES[palette]
    data, views, accessors, meshes, nodes, runtime_parts, world = bytearray(), [], [], [], [], [], []
    def accessor(values, code, kind, target, low=None, high=None):
        while len(data) % 4:
            data.append(0)
        offset = len(data)
        flat = [n for row in values for n in row] if kind == "VEC3" else values
        data.extend(struct.pack(f"<{len(flat)}{code}", *flat))
        views.append(dict(buffer=0, byteOffset=offset, byteLength=len(data)-offset, target=target))
        entry = dict(bufferView=len(views)-1, componentType=5126 if code == "f" else 5123,
                     count=len(values), type=kind)
        if low is not None:
            entry.update(min=low, max=high)
        accessors.append(entry)
        return len(accessors)-1
    for name, centre, size, radius, material in parts(width, depth, height, seats, style):
        positions, normals, indices = rounded_box(size, radius)
        translated = [[p[i] + centre[i] for i in range(3)] for p in positions]
        world.extend(translated)
        low = [min(p[i] for p in positions) for i in range(3)]
        high = [max(p[i] for p in positions) for i in range(3)]
        a = accessor(positions, "f", "VEC3", 34962, low, high)
        b = accessor(normals, "f", "VEC3", 34962)
        c = accessor(indices, "H", "SCALAR", 34963)
        meshes.append({"primitives": [dict(attributes={"POSITION": a, "NORMAL": b}, indices=c, material=material)]})
        nodes.append(dict(name=name, translation=centre, mesh=len(meshes)-1))
        # Unity uses the same left-handed coordinates as the room plan.
        # Mirror glTF Z, reverse winding, keep metres and unscaled mesh vertices.
        triangles = [n for i in range(0, len(indices), 3) for n in (indices[i], indices[i+2], indices[i+1])]
        runtime_parts.append(dict(name=name, vertices=[v for p in translated for v in (p[0], p[1], -p[2])],
            normals=[v for p in normals for v in (p[0], p[1], -p[2])], triangles=triangles,
            color=materials_in_use[material][1], roughness=materials_in_use[material][2]))
    bounds = [max(p[i] for p in world) - min(p[i] for p in world) for i in range(3)]
    assert all(abs(a-b) < 1e-6 for a,b in zip(bounds, (width, height, depth))), bounds
    assert abs(min(p[1] for p in world)) < 1e-6
    while len(data) % 4:
        data.append(0)
    materials = [{"name": n, "pbrMetallicRoughness": dict(baseColorFactor=c, metallicFactor=0, roughnessFactor=r)}
                 for n,c,r in materials_in_use]
    model = dict(asset={"version": "2.0", "generator": "Almutlaq reconstructed demo, visual approval required"},
        scene=0, scenes=[{"nodes": list(range(len(nodes)))}], nodes=nodes, meshes=meshes, materials=materials,
        buffers=[{"byteLength": len(data)}], bufferViews=views, accessors=accessors)
    header = json.dumps(model, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    glb = struct.pack("<4sII", b"glTF", 2, 28+len(header)+len(data))
    glb += struct.pack("<I4s", len(header), b"JSON") + header
    glb += struct.pack("<I4s", len(data), b"BIN\0") + data
    output.mkdir(parents=True, exist_ok=True)
    (output / f"{stem}.glb").write_bytes(glb)
    runtime = dict(formatVersion=1, unit="m", width=width, depth=depth, height=height,
                   visuallyApproved=False, parts=runtime_parts)
    runtime_bytes = json.dumps(runtime, separators=(",", ":"), allow_nan=False).encode()
    (output / f"{stem}.mesh.json").write_bytes(runtime_bytes)
    result = dict(file=f"{stem}.glb", sha256=hashlib.sha256(glb).hexdigest(), width=width, depth=depth,
                height=height, triangles=sum(len(p["triangles"])//3 for p in runtime_parts),
                runtimeFile=f"{stem}.mesh.json", runtimeSha256=hashlib.sha256(runtime_bytes).hexdigest())
    if sku:
        result["sku"] = sku
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "generated-models")
    args = parser.parse_args()
    results = [
        build(args.output, "london-10_14_3", 2.10, 1.03, 1.00, 3),
        build(args.output, "london-6_14_5", .84, .95, .94, 1),
        # Phone AR only (not in the room planner or headset yet). Size from the CityW product page.
        build(args.output, "cityw-23_88_1", 2.30, 1.01, .78, 3, style="square", palette="warm-beige", sku="23_88_1"),
    ]
    (args.output / "models-manifest.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
