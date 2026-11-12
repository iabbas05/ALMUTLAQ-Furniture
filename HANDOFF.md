# Handoff log

Newest entry first. Each agent adds an entry at the end of every work session, using the template at the bottom.

---

## 2026-11-12 · Claude · review of Codex `78dfc7e` to `5cc907b`

- Blocking: `Repair-PICOUnity66.ps1` patches `Library/PackageCache`, which Package Manager can restore at any time. Recommend an Editor version listed as supported by PICO SDK 3.4.0 instead; embedded package only if 6000.6 is required.
- `BuildFromEditor.cs`: unrelated test runs finishing first cancel the build; ignore non-matching runs instead.
- Client proposal (outside this repository) updated: virtual rebuilt room, one headset already available plus one for the pilot.
- Full comment on PR #4. Nothing compiled or run by Claude.

---

## 2026-11-11 · Claude · reply to the execution plan at `60898e8`

- Abbas confirmed PICO 4 Ultra to Claude directly. The earlier request to keep the Unity scene vendor-neutral is withdrawn.
- `docs/EXECUTION_PLAN.md` accepted with three revisions; findings on the PICO build path, Pages status and a prioritised blocker table are in the PR #4 comments.
- Proposal draft (outside this repository) updated to PICO 4 Ultra.
- Nothing in the Unity path was compiled or run by Claude; findings are from reading.

---

## 2026-11-11 · Claude · review of Codex `cb916b8`

- Codex's branch now contains PR #1, PR #2 and PR #3 by merge commit, plus its work on task groups A to E. The fuller, newer log is the `HANDOFF.md` on `codex/unified-room-v08`.
- Verified on Linux: 20 of 20 service tests, both USDZ files at published size. Read the launcher and the iOS Quick Look plugin; neither can run here.
- Open for Abbas: headset choice (Codex pinned the PICO SDK and reports Abbas confirmed it; not confirmed on my side), Unity licence sign-in, USB debugging, GitHub Pages, device checklist.
- Review comment with next tasks posted on PR #4.

---

## 2026-11-11 · Claude · task list for Codex posted

Abbas asked Claude to coordinate. The ordered task list for Codex (groups A to E, plus items on hold) is in the PR #4 comments, dated 2026-11-11. Codex: start with group A, and log each finished task here. Claude reviews each push.

---

## 2026-11-11 · Claude · check-in after Codex's push (PR #3 at `b2acdfa`, review of PR #4)

**Seen**
- Codex pushed `codex/unified-room-v08` (PR #4, `bf84ddc`, Actions passing) with the chair model, undo/redo, named designs, the local staff service, RoomPlan bridge and Unity sources. The "not found on any pushed branch" list in my first entry below is now resolved.

**Done**
- PR #3 restacked from PR #1 onto PR #4 (one force-push of my own branch; previous head `f15d008`).
- Web AR page now uses `tools/generate_demo_models.py` as the single model source, serves sofa and chair by `?sku=`, and rejects unsupported codes. `ar-preview/generate-model.py` removed.
- Review comment posted on PR #4.

**Tested**
- Model pipeline locally: sofa 14 meshes 2.10 × 1.00 × 1.03 m, chair 10 meshes 0.84 × 0.94 × 0.95 m.
- `server/test_showroom.py`: 16 of 16 pass on Linux, HTTP tests included.
- Page rendered in headless Chrome (Arabic, English, chair, unsupported code).
- Untested on device: AR Quick Look, Scene Viewer, WebXR, and the rendered look of the models.

**Not done / known problems**
- Flutter, Swift and Unity sources in PR #4 not reviewed line by line.
- `HANDOFF.md` and `AGENTS.md` differ between PR #2 and PR #4 and will conflict. Suggested merge order: #2, then #1, then #4 (rebased), then #3.
- PR #4's `AGENTS.md` lists decisions as approved by Abbas (Flutter in scope, PICO 4 Ultra, Unity on the phone). Abbas to confirm.

**Next**
- Abbas: confirm those decisions, merge in the order above, enable GitHub Pages, test the page on a phone.
- Codex: items 1 to 4 in the PR #4 review comment.
- Claude: re-test PR #3 after PR #4 changes; deeper review of the Flutter room link and the service on request.

---

## 2026-11-11 · Claude · branch `claude/ar-preview-web` (PR #3)

**Done**
- Branched from `native-live-catalogue` at `d48e80c`; PR #3 is stacked on PR #1.
- `generate-usdz.py`: meshes bound to UsdPreviewSurface materials.
- New `check-usdz.py`: asserts size, floor contact and material bindings.
- `index.html`: Arabic and English, broken characters fixed, WebXR mode added.
- New workflow `ar-preview.yml`: builds GLB and USDZ, uploads the site, deploys to GitHub Pages on `main`.
- Fixes open problems 1 and 2 below once merged and Pages is enabled.

**Tested**
- Scripts run locally; USDZ opens in usd-core, 14 meshes, 2.10 × 1.00 × 1.03 m.
- Page text rendered in headless Chrome, both languages.
- Untested on device: AR Quick Look, Scene Viewer, WebXR in a headset browser.

**Not done / known problems**
- No chair page: waiting for Codex's chair model. Codex, when you push it, keep the same script pattern (`generate-model.py` writing `<name>-<code>.glb`) so the page and workflow can take a second product.
- GitHub Pages must be enabled once by Abbas.

**Next**
- Codex: push the chair model and the other unpushed work.
- Claude: add the chair page and a product switcher after that; review PR #1.

---

## 2026-11-11 · Claude · branch `claude/agent-handoff`

**Done**
- Added `AGENTS.md` (shared rules), `CLAUDE.md` (points to it) and this log.
- Reviewed `main` and `native-live-catalogue` (PR #1). Findings below.

**State of `native-live-catalogue` as pushed (commit `d48e80c`)**
- Fixed: Arabic text encoding; Noto Sans Arabic font added.
- Improved: London sofa model, 14 parts with rounded edges; dimensions checked by a test.
- Added: 2D room plan, 3D orbit view, rotation, keeping items inside the room.
- Chair: dimensions listed, no 3D model yet.

**Described by Codex as done, but not found on any pushed branch**
- London chair 3D model
- Undo and redo, saving a design by name
- Local service storing customer name and phone with consent, design version number, headset confirmation

Codex: please push these so they can be reviewed.

**Known problems still open**
1. `ar-preview/index.html` requests `london-10_14_3.usdz`, but the workflow never generates or publishes it, so iPhone AR fails from the web page.
2. `ar-preview` is not published anywhere; the in-app AR button only appears when a URL is passed at build time.
3. The iOS build produces an unsigned IPA, so it cannot be installed on an iPhone without signing. (Actions passes on `d48e80c`, so the build itself works.)
4. `BUILD.md` says catalogue, prices and checkout come from the live websites; check it still matches the code.
5. Untested on device: whether `model_viewer_plus` needs extra Android settings.

**Next**
- Abbas: answer the open questions in `AGENTS.md`.
- Codex: push the unpushed work to `native-live-catalogue` and update this log.
- Claude: review PR #1 once updated; fix the USDZ generation and publishing of `ar-preview` on a `claude/` branch.

---

## Template

```
## YYYY-MM-DD · <agent> · branch `<branch>`

**Done**
- 

**Tested** (how, and on which device; or "untested on device")
- 

**Not done / known problems**
- 

**Next**
- 
```
