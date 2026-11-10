# Handoff log

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
