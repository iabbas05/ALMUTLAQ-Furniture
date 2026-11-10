"""Open the generated USDZ and confirm size, floor contact and materials."""
from pathlib import Path

from pxr import Usd, UsdGeom, UsdShade

stage = Usd.Stage.Open(str(Path(__file__).with_name("london-10_14_3.usdz")))
root = stage.GetDefaultPrim()
assert root, "USDZ has no default prim"
assert UsdGeom.GetStageMetersPerUnit(stage) == 1
meshes = [prim for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
assert meshes, "USDZ has no meshes"
for prim in meshes:
    assert UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0], prim.GetPath()
box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ["default"]).ComputeWorldBound(root).ComputeAlignedRange()
size = [round(axis, 4) for axis in box.GetSize()]
assert size == [2.10, 1.00, 1.03], size
assert abs(box.GetMin()[1]) < 1e-6, "model does not rest on the floor"
print(f"{len(meshes)} meshes, {size} m, all materials bound")
