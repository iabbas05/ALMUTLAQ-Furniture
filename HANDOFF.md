# Handoff log

## 2026-11-11 · Codex · branch codex/unified-room-v08 · review checkpoint

Status: work in progress. This checkpoint is uploaded for review and is not a release-readiness claim.

Written and uploaded in this checkpoint:
- Dimensioned London sofa and chair generator in tools/generate_demo_models.py. GLB and matching Unity mesh JSON, immutable model metadata.
- Shared metre-based room contract. Whole rotated footprints, named designs, undo/redo, send/ACK UI, catalogue cache/filter/sort/compare work.
- Local-only Python/SQLite service, one-time pairing, optimistic revisions, customer permission, device privacy boundaries, draft GLB upload and explicit publish logic.
- Native RoomPlan bridge and CI preparation. Hardware support gate and draft measurement review. Nonrectangular scans do not replace the current room with a bounding rectangle.
- Release checking/download UI. Signing and actual update install are separate concerns.

Validation at this checkpoint:
- Dart formatter passed for the edited sources before this commit.
- Generated GLB dimensions: sofa 2.10 × 1.03 × 1.00 m, chair 0.84 × 0.95 × 0.94 m. Geometry assertions pass.
- 11 local service/storage/model tests passed. 4 HTTP tests were blocked locally by Windows socket permissions (WinError 10013), not skipped in CI.
- GitHub Actions for this checkpoint: pending. Flutter, iOS compilation and HTTP integration must pass before a deliverable is called built.
- Untested on device: all new Flutter changes, RoomPlan and PICO.

Still being completed:
- Staff HTML/JS panel, Unity v2 network consumer and scene, one-command launcher, additional UI tests and final package.
- Unity is not embedded in Flutter yet. Current phone room view remains a Flutter-rendered preview.
- Checkout/ERP/live stock and full website product count are not verified.
- Models are reconstructions, not manufacturer-approved CAD or scans.
- The local GLB importer supports static triangle geometry and solid materials only. Production textured imports need the glTFast path.

Coordination for Claude:
- Read AGENTS.md: the Flutter/Unity/PICO/location/customer-save questions were already answered by Abbas in this conversation.
- Keep website AR and USDZ changes on claude/ branches. This checkpoint deliberately adds a separate generator under tools/ to avoid overwriting your web generator.
- The same GLB+USDZ should eventually come from one approved model version. Please review tools/generate_demo_models.py and coordinate the USDZ export.
- Please review this branch/PR. Do not merge it while this entry still says pending.
- The full commercial budget is kept in a private planning deliverable, not in this public repository.

---


Newest entry first. Each agent adds an entry at the end of every work session, using the template at the bottom.

---

## 2026-11-11 · Claude · branch `claude/agent-handoff`

**Done**
- Added `AGENTS.md` (shared rules), `CLAUDE.md` (points to it) and this log.
- Reviewed `main` and `native-live-catalogue` (PR #1). Findings below.

**State of `native-live-catalogue` as pushed (commit `d48e80c`)**
- Fixed: Arabic text encoding; Noto Sans Arabic font added.
- Improved: London sofa model, 17 parts with rounded edges; dimensions checked by a test.
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
3. The iOS build produces an unsigned IPA, and the latest `main` commit suggests the build fails. The `ios-build.log` artifact from Actions is needed.
4. `BUILD.md` says catalogue, prices and checkout come from the live websites; check it still matches the code.
5. Untested here: Flutter version `3.47.8` in the workflow, and whether `model_viewer_plus` needs extra Android settings.

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
