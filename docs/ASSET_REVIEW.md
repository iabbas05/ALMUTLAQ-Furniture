# Free-first furniture asset trial

Official reference views and the metre dimensions are in `tools/furniture_references.json`. The isolated views avoid asking a generator to reconstruct the lifestyle room, coffee table or surrounding furniture. Single-image generation still invents unseen geometry; the other views are review evidence, not proof that a generated back is correct.

## Generate one draft

Download the selected three-quarter photo from the reference manifest to a local image file, then run:

```powershell
python tools/trellis_free_trial.py --input sofa-reference.jpg --output builds/trellis-sofa-trial --sku 10_14_3
```

This uploads the input to Microsoft's official TRELLIS.2 Hugging Face Space. It uses that public service's queue, not a paid API. Access is subject to its availability, account requirements and quota. An optional `HF_TOKEN` is read from the environment and is never a command argument or log field. Keep it outside the repository and never paste it into chat. The tool does not create accounts, buy credits, change network routes or retry a submitted task automatically. `trial.json` records success or the actual stop reason. A failed call is not a generated model. The first complete authenticated generation/export has not yet been validated.

The actual 26 November trial stopped during preprocessing with the service's ZeroGPU runs-limit/authentication message. No image-generated furniture was substituted into the app.

## Prepare and review a generated GLB

```powershell
blender -b --python tools/prepare_furniture_asset.py -- --input builds/trellis-sofa-trial/product-draft.glb --output builds/review-sofa --sku 10_14_3 --width 2.10 --depth 1.03 --height 1.00 --fit-width
```

Outputs: `product.glb`, editable packed `product.blend`, `audit.json`, and front/side/back PNG review views. `--fit-width` applies one uniform scale. Depth/height mismatches remain visible in the report instead of stretching the model into a false match. Without the flag, the existing metre scale is audited unchanged. Axis conversion is handled by Blender's glTF import/export: Blender X/Y/Z represent width/depth/height; exported glTF uses Y-up.

The five-millimetre check concerns digital bounding dimensions only. It does not certify shape, fabric, real tracking accuracy or purchasing suitability. Every output stays `draft_requires_visual_approval`, including a dimensionally passing asset. No app, staff product, headset model or catalogue version is replaced by this command.

Use a fresh output directory for each review. The pipeline accepts embedded static GLB, refuses external texture/buffer URLs, preserves original embedded image bytes, and stops if a textured source loses all exported textures. Arbitrary material extensions still need inspection on each target renderer. Automatic decimation and textured USDZ export are not implemented. The available Blender 4.3.2 build was used for real validation; no claim of Blender 5.2 testing is made.

## Verification

```powershell
python qa/check_asset_review.py
```

Set `BLENDER` to the executable path if it is not on PATH. The real Blender check builds a clearly labelled synthetic textured box and verifies embedded texture survival, packed editable output, uniform scale and rejection of the intentionally wrong depth. It does not create or certify a furniture product. GitHub's dedicated asset-review workflow runs this check without online generation or credentials.

Acceptance still requires matching the real reference views, approved measurements and fabric, successful GLB/USDZ rendering, an appropriate mesh/texture performance budget, and real phone/PICO tests. Existing Flutter/staff/Unity demo renderers and the USDZ exporter still need their production texture support before these drafts become usable shared catalogue assets.
