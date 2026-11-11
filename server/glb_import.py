"""Restricted, dimension-checked static GLB import for the local Unity demo.
Supports embedded triangle meshes and solid PBR colours. Textures, skins,
animation and required extensions need the production glTFast import path.
"""
import json
import math
import struct

class ModelError(ValueError):
    pass

def finite(values):
    return all(isinstance(n, (int, float)) and not isinstance(n, bool) and math.isfinite(n) for n in values)

def mul(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

IDENTITY = [[1.,0,0,0],[0,1.,0,0],[0,0,1.,0],[0,0,0,1.]]

def transform(node):
    if "matrix" in node:
        m = node["matrix"]
        if len(m) != 16 or not finite(m):
            raise ModelError("Invalid node matrix")
        return [[m[col*4+row] for col in range(4)] for row in range(4)]
    t, q, s = node.get("translation", [0,0,0]), node.get("rotation", [0,0,0,1]), node.get("scale", [1,1,1])
    if len(t) != 3 or len(q) != 4 or len(s) != 3 or not finite(t+q+s):
        raise ModelError("Invalid node transform")
    x,y,z,w = q
    norm = math.sqrt(x*x+y*y+z*z+w*w)
    if norm < 1e-8 or any(abs(n) < 1e-8 for n in s):
        raise ModelError("Singular transform")
    x,y,z,w = [n/norm for n in q]
    r = [[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
         [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
         [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]]
    return [[r[i][j]*s[j] for j in range(3)] + [t[i]] for i in range(3)] + [[0,0,0,1]]

def decode_glb(blob, expected):
    if not 28 <= len(blob) <= 15*1024*1024:
        raise ModelError("GLB must be between 28 bytes and 15 MB")
    magic, version, length = struct.unpack_from("<4sII", blob)
    if magic != b"glTF" or version != 2 or length != len(blob):
        raise ModelError("Invalid GLB header")
    chunks, at = {}, 12
    while at < len(blob):
        if at + 8 > len(blob):
            raise ModelError("Truncated chunk")
        size, kind = struct.unpack_from("<I4s", blob, at)
        at += 8
        if size % 4 or at + size > len(blob) or kind in chunks:
            raise ModelError("Invalid GLB chunk")
        chunks[kind] = blob[at:at+size]
        at += size
    try:
        doc = json.loads(chunks[b"JSON"])
        binary = chunks[b"BIN\0"]
        if doc.get("asset", {}).get("version") != "2.0":
            raise ModelError("Only glTF 2.0 is supported")
        if doc.get("extensionsRequired") or doc.get("animations") or doc.get("skins") or doc.get("textures"):
            raise ModelError("Use a static GLB with solid materials for the local demo. Production textured GLB needs glTFast.")
        buffers = doc["buffers"]
        if len(buffers) != 1 or "uri" in buffers[0] or buffers[0]["byteLength"] > len(binary):
            raise ModelError("Only a single embedded buffer is supported")
        views, accessors = doc["bufferViews"], doc["accessors"]
        def read(index, kind):
            a = accessors[index]
            if a.get("sparse") or a["type"] != kind:
                raise ModelError("Unsupported accessor")
            v = views[a["bufferView"]]
            if v.get("buffer", 0) != 0:
                raise ModelError("Invalid buffer view")
            component = a["componentType"]
            if kind == "VEC3" and component != 5126:
                raise ModelError("Positions must be floating-point VEC3")
            if kind == "SCALAR" and component not in (5121, 5123, 5125):
                raise ModelError("Unsupported indices")
            code, width = {5126: ("f",4), 5121: ("B",1), 5123: ("H",2), 5125: ("I",4)}[component]
            count, n = a["count"], 3 if kind == "VEC3" else 1
            if not isinstance(count, int) or not 1 <= count <= 150000:
                raise ModelError("Mesh is too large")
            stride = v.get("byteStride", n*width)
            offset = a.get("byteOffset", 0)
            if (not isinstance(stride, int) or stride < n*width or stride > 252 or offset < 0
                or offset + (count-1)*stride + n*width > v["byteLength"]
                or v.get("byteOffset", 0) + v["byteLength"] > len(binary)):
                raise ModelError("Accessor exceeds its buffer")
            out = [struct.unpack_from("<" + code*n, binary, v.get("byteOffset",0)+offset+i*stride)
                   for i in range(count)]
            if not all(finite(row) for row in out):
                raise ModelError("Non-finite coordinates")
            return [row[0] for row in out] if kind == "SCALAR" else out

        nodes, meshes, materials = doc["nodes"], doc["meshes"], doc.get("materials", [])
        parts, world_points, total_triangles = [], [], 0
        def visit(index, parent, lineage):
            nonlocal total_triangles
            if index in lineage or len(lineage) > 64:
                raise ModelError("Invalid node hierarchy")
            node = nodes[index]
            m = mul(parent, transform(node))
            if "mesh" in node:
                for primitive in meshes[node["mesh"]]["primitives"]:
                    if primitive.get("mode", 4) != 4:
                        raise ModelError("Only triangle meshes are supported")
                    source = read(primitive["attributes"]["POSITION"], "VEC3")
                    vertices = [[sum(m[i][j]*p[j] for j in range(3)) + m[i][3] for i in range(3)] for p in source]
                    indices = read(primitive["indices"], "SCALAR") if "indices" in primitive else list(range(len(vertices)))
                    if len(indices) % 3 or any(i < 0 or i >= len(vertices) for i in indices):
                        raise ModelError("Invalid triangle indices")
                    total_triangles += len(indices)//3
                    if total_triangles > 50000:
                        raise ModelError("Use at most 50000 triangles")
                    material = materials[primitive["material"]] if "material" in primitive else {}
                    if material.get("alphaMode", "OPAQUE") != "OPAQUE":
                        raise ModelError("Transparent materials need the production importer")
                    pbr = material.get("pbrMetallicRoughness", {})
                    color = pbr.get("baseColorFactor", [1,1,1,1])
                    if len(color) != 4 or not finite(color) or not all(0 <= c <= 1 for c in color):
                        raise ModelError("Invalid material colour")
                    world_points.extend(vertices)
                    # Preserve the geometry. Translation to floor-centre is applied below, never scaling.
                    parts.append(dict(name=node.get("name", "Furniture part")[:80], vertices=vertices,
                        triangles=[n for i in range(0,len(indices),3) for n in (indices[i],indices[i+2],indices[i+1])],
                        normals=[], color=color, roughness=float(pbr.get("roughnessFactor", 1))))
            for child in node.get("children", []):
                visit(child, m, lineage | {index})
        for index in doc["scenes"][doc.get("scene",0)]["nodes"]:
            visit(index, IDENTITY, set())
        if not world_points:
            raise ModelError("No visible mesh")
        lo = [min(p[i] for p in world_points) for i in range(3)]
        hi = [max(p[i] for p in world_points) for i in range(3)]
        extents = [hi[i]-lo[i] for i in range(3)]
        for actual, wanted in zip(extents, [expected["width"], expected["height"], expected["depth"]]):
            if abs(actual-wanted) > .005:
                raise ModelError("Model dimensions differ by more than 5 mm. Correct the source model, do not stretch it.")
        centre = [(lo[0]+hi[0])/2, lo[1], (lo[2]+hi[2])/2]
        for part in parts:
            part["vertices"] = [n for p in part["vertices"] for n in
                (p[0]-centre[0], p[1]-centre[1], -(p[2]-centre[2]))]
        return dict(formatVersion=1, unit="m", width=expected["width"], depth=expected["depth"],
                    height=expected["height"], visuallyApproved=False, parts=parts)
    except ModelError:
        raise
    except (KeyError, IndexError, TypeError, ValueError, struct.error, OverflowError) as error:
        raise ModelError("Unsupported or malformed GLB") from error
