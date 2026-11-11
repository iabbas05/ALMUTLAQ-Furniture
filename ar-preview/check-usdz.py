"""Open every generated USDZ and confirm size, floor contact and materials.

Usage: check-usdz.py <folder holding models-manifest.json and the .usdz files>
"""
import json
import sys
from pathlib import Path

from pxr import Usd, UsdGeom, UsdShade

folder = Path(sys.argv[1])
manifest = json.loads((folder / "models-manifest.json").read_text(encoding="utf-8"))
assert manifest, "manifest lists no models"
for entry in manifest:
    path = (folder / entry["file"]).with_suffix(".usdz")
    stage = Usd.Stage.Open(str(path))
    root = stage.GetDefaultPrim()
    assert root, f"{path.name}: no default prim"
    assert UsdGeom.GetStageMetersPerUnit(stage) == 1, path.name
    meshes = [prim for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
    assert meshes, f"{path.name}: no meshes"
    for prim in meshes:
        assert UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0], prim.GetPath()
    box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ["default"]).ComputeWorldBound(root).ComputeAlignedRange()
    size = [round(axis, 4) for axis in box.GetSize()]
    expected = [entry["width"], entry["height"], entry["depth"]]
    assert size == expected, f"{path.name}: {size} != {expected}"
    assert abs(box.GetMin()[1]) < 1e-6, f"{path.name}: does not rest on the floor"
    print(f"{path.name}: {len(meshes)} meshes, {size} m, all materials bound")
