# Handoff log

## 2026-11-12 · Claude · branch `claude/app-ar-review` (stacked on `codex/unified-room-v08`)

Abbas asked Claude this session to fix the iPhone build, extend AR, redesign the app (including the room planner) and review the code, and explicitly allowed Claude to change the Flutter app for this work. Codex: please review.

**Done**
- iPhone build: CI already builds an unsigned IPA on `main` and PR #4. Added optional signing to `build-mobile.yml`: with secrets `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` it exports a signed IPA (method taken from the profile) as Almutlaq-Signed-IPA. Skipped when the secrets are absent. Steps in `BUILD.md`.
- AR: added the CityW Warm Beige three-seater `23_88_1` (230 × 101 × 78 cm from the product page) as a square-arm, wooden-leg model in `tools/generate_demo_models.py`, file stem `cityw-23_88_1`. London outputs are byte-identical to before. `lib/product_ar.dart` now holds the one list of phone-AR products; the iOS plugin opens the bundled USDZ path Dart sends (validated to `assets/<name>.usdz`) instead of a hard-coded SKU list. The web page serves the new product. It is phone 3D/AR only: not added to `furnitureSizes`, the room planner, the staff service or Unity.
- Design: new storefront (store switch, room banner, search with a filter sheet, product cards with 3D badge), product page (gallery with dots and full-screen zoom, dimension tiles, "See it in your space" card, fixed Add to bag bar), bag across both stores with thumbnails, empty states, theme. Room planner regrouped into sections (room size, view, selected piece, add furniture, doors and windows, my designs, showroom); rotate both ways; saved designs listed by name and deletable.
- Fixed: the bag only listed products from the currently selected store.

**Tested**
- Local Flutter 3.47.8: `flutter analyze lib test` clean, 16 tests pass (new: every AR model matches its published size; AR-only products stay out of the planner; product page and bag render). 20 server tests pass. All three USDZ files pass `check-usdz.py`.
- CI on e832615: mobile workflow 43200769639 passed (Windows, protocol/browser, Android APK, unsigned iOS IPA); AR workflow 43200774801 passed.
- Untested on device. Signing steps untested until real signing material is added. Store photos could not be fetched in this environment, so screenshots used placeholders.

**Review notes, not fixed**
1. `dart format lib test` in CI rewrites files but never fails; add `--set-exit-if-changed` (would reformat `catalogue.dart` and `room_link.dart`).
2. The Arabic font is downloaded from the `main` branch of google/fonts at build time; pin a commit for reproducible builds.
3. Live catalogue sizes show WooCommerce length × width × height with "(source units)", a different order and unit label from the sample W × D × H in cm.
4. `room_drawing.dart` decides seat count by SKU (`6_14_5` → 1); `LondonMesh` reads only float positions and 16-bit indices without textures, so photo-generated textured models need conversion first.
5. Protocol job runs `generate-usdz.py` twice.
6. `main` still has broken Arabic text (replacement characters) in `lib/main.dart` and `ar-preview/index.html`; merging PR #4 fixes it.

**Next**
- Codex: review this branch; decide whether `23_88_1` should join the planner and headset.
- Abbas: add iOS signing secrets if an installable IPA is wanted; supply approved photos/CAD.

## 2026-11-11 - Codex - real package import and PICO EntityId compatibility

- User reported PICO SpatialAudio CS0619 at SceneGeometry.cs:414 after opening the project. The old Integration SDK's baked filename uses GetInstanceID, removed in Unity 6.6.
- Compared official PICO-Unity-SDK XR/SpatialAudio source at main 673b0f84355585c45aaf0ba477d48f480472e51d, which uses UNITY_6000_4_OR_NEWER with EntityId.ToULong(GetEntityId()). Added Repair-PICOUnity66.ps1 to apply that narrow conditional to the pinned 3.4.0 cache, keeping a local ignored backup and refusing unexpected source. No SDK-wide migration or vendor source redistribution. Ran it successfully and verified idempotence. Reapply after refreshing the vendor package cache.
- Observed generated lock now resolves XR Management 4.7.0 without legacy VR module. Fresh Almutlaq/PICO/Spatializer/test DLLs appeared in Library/ScriptAssemblies during the user's real import; this is substantially beyond prior runtime-only checks.
- Updated BuildShowroom to XR 4.7 settingsKey and Manager APIs. Independent Roslyn compilation of both Assets/Editor scripts against installed Unity modules, actual resolved project/vendor/test assemblies and the netstandard mscorlib shim passed with zero output/exit 0. Initial missing/duplicate reference setup errors in this standalone check were corrected before the successful run.
- This is Editor-source compilation evidence, not edit-mode test execution, IL2CPP/APK packaging or physical acceptance. The user should enter Safe Mode/retry resolution and let the actual Editor recompile. A stale dialog may still show the old 4.5.0 error; on-disk manifest and fresh lock now select 4.7.0. New CI pending.


## 2026-11-11 - Codex - Unity 6.6 missing VR module package fix

- User reached real package resolution and reported XR Management 4.5.0 requesting unavailable com.unity.modules.vr@1.0.0. Confirmed the module is absent from this installed Editor, and the generated lock recorded that legacy dependency.
- Pinned XR Management 4.7.0, the Unity 6000.6 released package per official documentation. Unity's XR Management changelog records removal of the old VR dependency in later versions. PICO SDK pin unchanged.
- Validated manifest JSON, selected XR version, and existence of every directly declared built-in module against the installed Editor. Backed up the stale generated lock under ignored builds/ and removed only the local generated lock so Unity can resolve again. Did not delete Library or vendor package source.
- User should click Retry in the existing resolution dialog. Actual full dependency resolution, Editor/PICO compilation and APK still require observation; this edit is not a build pass. New CI pending.
- Sources: https://docs.unity.com/en-us/engine/6000.6/manual/packages-list/packages-all/pack-safe/com-unity-xr-management and https://docs.unity3d.com/Packages/com.unity.xr.management@4.7/changelog/CHANGELOG.html


## 2026-11-11 - Codex - assembly-name gate correction

- Editor review found the run-tree gate used GetFileNameWithoutExtension on an assembly display name. For a name without .dll this would strip .Tests and reject the intended run. The gate now accepts only the exact showroom assembly name with or without .dll. Full Editor execution remains unverified; no APK success claimed. New CI pending.


## 2026-11-11 - Codex - completion audit and precise remaining steps

- Corrected the scope of earlier time estimates: elapsed preparation/source-check time was not a complete build. No fixed full-product completion estimate is established by these results.
- Added Build-Headset.ps1 -PrepareOnly to generate both resources without opening Unity, requiring an Editor installation or touching ADB. Eight simulated build/preparation regression cases pass locally; fifteen storage tests pass.
- Hardened in-Editor build callback: startup errors clean up, and the result must match a run tree containing only Almutlaq.Showroom.Tests before packaging. These Editor changes remain uncompiled/unexecuted in real Unity; do not count local runtime C# checks as their validation.
- Verified workflow 43009850101 fully passed on 15e0c55 (Windows, protocol/browser, Flutter tests/analysis, Android APK and unsigned IPA); AR workflow 43009849653 passed. New checkpoint CI pending.
- docs/DELIVERY_STATUS.md records verified outputs, written-but-unvalidated Editor work, desktop build steps, physical acceptance steps, external account/asset dependencies and unfinished engineering separately. Runbook updated to avoid starting blocked Unity merely to prepare models.
- Latest batch Unity attempt crashed after licence IPC/Burst/Mono socket failures. No headset APK or successful Unity edit-mode report exists. No connected headset is required for the build, only for physical acceptance.
- Do not introduce new product features before the agreed first-device gate. Phone Unity embedding, passthrough, commercial integrations and production models remain unfinished work, not owner-only settings.


## 2026-11-11 - Codex - build inside the already-open Editor

- Added Almutlaq > Test and build PICO APK menu in BuildFromEditor.cs. Requires Android active target, finished compilation and model resources; prompts to save modified scenes. Runs only Almutlaq.Showroom.Tests through Unity Test Framework, saves unity-editor-tests.xml and refuses zero/failed tests. After callbacks unwind, builds a fresh pending APK and replaces the prior output only after success. No headset or ADB needed to build.
- This is source implementation only. The new Editor integration has not been compiled or executed in a functioning Editor. Runtime-source checks do not cover it. No claim of an APK or device acceptance.
- API usage checked against Unity Test Framework documentation (TestRunnerApi, ICallbacks, ITestResultAdaptor and SaveResultToFile). Full Editor/PICO import is still a required gate.
- CUA inventory again shows Unity Hub only, no Unity Editor project window. The batch attempt remains blocked by licence-client IPC. Do not repeatedly restart the same blocked batch path or disable licensing checks.
- Prior code mobile workflow 43009201854 was cancelled when superseded; latest existing workflow 43009342541 was in progress at the last check. New checkpoint CI pending. Runbook includes the in-Editor build route; Claude review requested.


## 2026-11-11 - Codex - second Editor attempt remains licence-IPC blocked

- Retried Build-Headset.ps1 after Abbas reported Unity open. Both model assets generated. Editor log again reports LicenseClient-iAbba connection refused, 60-second timeout and licensing initialization failure. No unity-tests.xml and no ShowroomVR-Linked.apk at the latest check. The process may retry internally; this is blocked, not a passing build.
- CUA inventory showed Unity Hub rather than an Editor project. The Hub access attempt timed out awaiting computer-use app approval. No user window was closed or licence settings changed.
- Runtime-source Editor/Android compilation passes; full Editor/PICO/IL2CPP still unverified. AR workflow 43009201946 passed on 78dfc7e; mobile workflow 43009201854 remains in progress.
- Claude review changes are published and reported in PR comment 6794162521. A working desktop Editor session with reachable licensing IPC is still needed. Physical device tests, Pages prerequisites, iPhone signing and CAD approval remain open.


## 2026-11-11 - Codex - Claude plan revisions implemented

- Applied Claude comment 6793749880: explicit Standard shader failure, pinned PICO SDK commit in loader failure, source-check output explicitly excludes asmdef resolution and Assets/Editor.
- EXECUTION_PLAN now records Claude acceptance with revisions, rendered-room/no-passthrough scope, development-only HTTP transport release blocker, proposal/client-document ownership and both Pages prerequisites (merge to main plus Pages enabled).
- Editor and Android runtime-source compilations pass locally after the update. Editor build-script changes still need actual Unity compilation; no false pass claimed.
- User reports Unity open. UI inventory showed Unity Hub only; the attempt to access its window timed out awaiting computer-use approval. Started another Build-Headset.ps1 attempt after that report. Result pending at upload, headset not required or installed.
- Device tests, iPhone signing, CAD/visual approval and actual Pages deployment remain open. No main merge performed while PR remains draft with device/build gates outstanding.
- CI pending on this checkpoint; last full passing code build remains workflow 43003769899. Claude notified through PR #4 after publication.


## 2026-11-11 - Codex - PICO build preparation and joint execution plan

- Abbas requested the unsigned IPA and preparation of PICO without connecting the headset, then explicitly requested a full plan and communication with Claude to assess the best route.
- Retrieved IPA artifact 13847287869 from successful workflow 43003769899. It is unsigned and needs signing for normal iPhone installation.
- Added Test-HeadsetSource.ps1: runtime C# compiles for both Editor and Android conditional symbols against installed Unity 6000.6.8f1 reference assemblies using Roslyn. Both pass locally. CS0649 warnings concern JSON-populated fields. This excludes PICO/editor source, edit-mode tests, IL2CPP and APK packaging; no headset build pass is claimed.
- Added docs/EXECUTION_PLAN.md with architecture recommendation, dependency stages, owners, completion gates, device-independent work and a six-item Claude review request. Proposed sequence: PICO build, first device pass, hosted phone AR, then phone Unity integration and commercial features. Claude has not yet accepted this new plan.
- Full Unity execution remains blocked in this automated environment by the observed IPC/socket crash. A headset is not needed to build; physical acceptance remains a separate gate. No licence bypass or environment restriction workaround attempted.
- New CI pending for this upload. Last complete mobile/AR pass is recorded above.


## 2026-11-11 - Codex - verified build and artifacts

- Mobile workflow 43003769899 completed successfully on code checkpoint 8139f1d: Windows launcher and seven simulated Unity build scenarios, protocol/storage/HTTP tests, staff browser checks, Flutter analysis/tests, Android APK and unsigned iOS IPA all passed. AR workflow 43003769966 passed.
- Confirmed downloadable artifacts: Android 13847901170; unsigned IPA 13847287869; app screenshots 13847412713; staff previews 13847875356; model outputs 13847770781. Run URL: https://github.com/iabbas05/ALMUTLAQ-Furniture/actions/runs/43003769899
- Documentation-only continuation e12bf964 records the desktop Unity/ADB steps requested by Claude. Documentation publication approval is resolved.
- Untested on device: PICO, phone AR and RoomPlan. Unity Editor compilation is not covered by mobile CI. The actual local attempt crashed in licensing IPC/Burst/Mono socket initialization; no headset APK was produced. Physical first-run steps are in docs/DEMO_RUNBOOK.md. This is a reviewable development checkpoint, not a completed commercial deployment.


## 2026-11-11 - Codex - desktop runbook publication approved

- Abbas explicitly approved the expanded docs/DEMO_RUNBOOK.md and HANDOFF.md upload, and authorized continued work without repeated approval questions.
- Build safeguards published at 8139f1d. Windows launch/build-script checks, protocol/HTTP/browser checks, Flutter analysis/tests and AR packaging passed. Mobile packaging workflow 43003769899 still running at this checkpoint.
- Added exact desktop Unity licence/package/build and USB debugging/ADB steps, with the pairing-code launch-extra limitation and Android HTTPS-hosting dependency requested in Claude review 6792129818.
- This documentation upload resolves the prior approval block. Unity/PICO compilation and physical device acceptance remain pending because the automated Windows session crashed during licensing IPC/Burst/Mono socket startup. Full phone Unity embedding and commercial integrations remain open.


## 2026-11-11 · Codex · publication authorized

- Abbas explicitly authorized publishing all five build/test/handoff changes to this Codex branch after automatic review requested confirmation. New CI pending at upload. Seven build-script scenarios and fifteen storage tests passed locally. Unity/PICO compilation and device testing remain blocked by the observed local IPC/socket crash.


## 2026-11-11 � Codex � local build safeguards, publication blocked

- Seven simulated Unity process/build scenarios pass in scripts/test_headset_build.ps1. Fifteen local StoreTests pass. PowerShell syntax checks pass.
- Build-Headset.ps1 rejects missing/empty results and zero passed tests, produces a fresh pending APK and promotes it only on success, retaining the prior APK on failure. Staff service launch uses a hidden window. CI configuration includes the new build-script checks.
- Mobile workflow 42994652687 and AR workflow 42994652671 succeeded on cb916b8. These new local changes are not published or verified in CI yet.
- GitHub create_tree publication was rejected by automatic approval review, which flagged potential disclosure of internal content to an unverified external repository and requested explicit payload/destination authorization. No alternative publication route attempted.
- Actual Unity launch crashed after licensing IPC and Burst named-pipe failures, in Mono socket IO/BuildReportRestService. ADB daemon startup is also blocked in this execution session. No headset APK or physical acceptance pass.
- Next: authorize publication of the five changed build/test/handoff files to codex/unified-room-v08, run CI, then perform Unity/PICO acceptance in a desktop session with working licence and IPC. Full phone Unity embedding and commercial integrations remain open.


## 2026-11-11 � Codex � Claude review follow-up

- A: updated BUILD.md, model-source note in AGENTS.md, and synchronized the complete corrected Claude history from 8cfbd83. Preserved the approved decisions from this conversation. Integrate source ancestry using a merge commit on the Codex branch, without force pushing an active branch or merging main.
- B: added the one-command USB launcher, detailed DEMO_RUNBOOK.md and physical DEVICE_TESTS.md. A Windows CI job now parses both PowerShell scripts and tests repeat startup preserving a TEST design. Its result is pending; USB/device operations remain untested.
- C: web handoff now sends SKU plus ar/en language, with tests. Kept SHOWROOM_AR_URL configurable and no host URL before deployment.
- D: PICO 4 Ultra was explicitly confirmed in this conversation, so the headset project uses the pinned official PICO SDK. Added Unity edit-mode rejected-revision/opening tests. Build-Headset.ps1 now requires these edit-mode tests to pass before creating the APK. These tests are written, not run in the real Editor.
- E: 30-day default configurable retention, startup/policy purge and staff-only single-record export added. 20 Python tests pass locally, including retention, export and device access denial.
- CI 42987910845 on 9b6ffd7 passed protocol/browser, Flutter analysis/tests, Android APK and unsigned IPA. Both artifact types exist. This does not establish device acceptance.
- Downloaded and inspected actual Flutter/staff screenshots from that run. Corrected test icon-font loading/photo precache, left-to-right dimension strings and false triangle seams. The visual follow-up is pending a new CI run.
- The first CI 42987597570 failed due to Playwright's wait_for_function conflicting with the page CSP. Replaced page-evaluated polling with controlled DevTools calls, preserving the application's CSP. The next browser run passed.


## 2026-11-11 � Codex � integrated build checkpoint 0.8.1+9

Written in this checkpoint:
- Integrate Claude's AR page, USDZ exporter, USD geometry validation and AR site workflow from claude/ar-preview-web (b2acdfa; supersedes f15d008) into the Codex branch. The page selects sofa/chair by SKU and rejects unknown products. No changes to Claude's branch or main.
- Bundle both USDZ files in the mobile build. Add iOS native AR Quick Look via ProductARPlugin with content scaling disabled. Android camera AR still needs a published HTTPS preview URL. RoomPlan remains the separate LiDAR scan bridge.
- Fix ModelAsset.Load's static/instance compiler error. Add a pinned PICO Integration SDK dependency, generated Unity scene and ARM64 development APK build entry point, Build-Headset.ps1.
- Add Start-LinkedDemo.ps1: generates models, starts the local service, discovers an authorized USB device, installs an available APK, verifies ADB reverse, obtains a one-time pairing code and launches the headset. No fixed serial or Downloads dependency.
- Add staff room 3D orbit view using the exact same published model triangles, including cutaway walls/windows. Editing remains in the measured plan.
- Restarting the local service now requires a fresh headset ACK. Support Arabic phone digits. Phone-to-showroom replacement reviews the current revision before sending.
- CI now checks the staff browser workflow and exports real Flutter/widget screenshots alongside the APK/IPA.

Validation here:
- 18 Python protocol/storage/HTTP tests passed on Linux, including actual loopback HTTP.
- Both USDZ files opened with usd-core, all materials bound, dimensions and floor contact verified: sofa 2.10 x 1.00 x 1.03 m (X,Y,Z), chair 0.84 x 0.94 x 0.95 m.
- JavaScript syntax and Python compilation passed.
- Local browser launch blocked by executor AF_UNIX socket permissions. Browser test is mandatory in CI, not counted as passed here.
- Flutter/Xcode/Unity/PowerShell runtimes are not installed in this executor. Mobile CI is pending for this commit. The new Unity build is not yet compiled in the real Unity Editor.
- Untested on device: native Quick Look, RoomPlan, all new Flutter changes and PICO runtime.

Still open:
- Embed full-screen Unity in the phone app. Current phone room renderer is Flutter, not embedded Unity.
- Run the new Unity project in licensed Unity 6000.6.8f1 with Android support, then test on Abbas's PICO. The local USB launcher is source-tested only until Windows validation.
- Real fabric/textured production models, CAD approval, full catalogue coverage, live stock/checkout APIs and account systems.
- HTTPS hosting for Android/web AR and company signing/distribution. No release published and no main merge.
- The local static GLB importer supports solid materials only and rejects textured/animated/required-extension assets.

Next: inspect CI on this checkpoint, repair failures, update this entry with the exact run and verified artifacts. Claude should independently review the integrated changes before Abbas merges.

---


## 2026-11-11 � Codex � branch codex/unified-room-v08 � review checkpoint

Status: work in progress. This checkpoint is uploaded for review and is not a release-readiness claim.

Written and uploaded in this checkpoint:
- Dimensioned London sofa and chair generator in tools/generate_demo_models.py. GLB and matching Unity mesh JSON, immutable model metadata.
- Shared metre-based room contract. Whole rotated footprints, named designs, undo/redo, send/ACK UI, catalogue cache/filter/sort/compare work.
- Local-only Python/SQLite service, one-time pairing, optimistic revisions, customer permission, device privacy boundaries, draft GLB upload and explicit publish logic.
- Native RoomPlan bridge and CI preparation. Hardware support gate and draft measurement review. Nonrectangular scans do not replace the current room with a bounding rectangle.
- Release checking/download UI. Signing and actual update install are separate concerns.

Validation at this checkpoint:
- Dart formatter passed for the edited sources before this commit.
- Generated GLB dimensions: sofa 2.10 ? 1.03 ? 1.00 m, chair 0.84 ? 0.95 ? 0.94 m. Geometry assertions pass.
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



## Shared Claude history, synchronized from 8cfbd83


Newest entry first. Each agent adds an entry at the end of every work session, using the template at the bottom.

---

## 2026-11-11 � Claude � task list for Codex posted

Abbas asked Claude to coordinate. The ordered task list for Codex (groups A to E, plus items on hold) is in the PR #4 comments, dated 2026-11-11. Codex: start with group A, and log each finished task here. Claude reviews each push.

---

## 2026-11-11 � Claude � check-in after Codex's push (PR #3 at `b2acdfa`, review of PR #4)

**Seen**
- Codex pushed `codex/unified-room-v08` (PR #4, `bf84ddc`, Actions passing) with the chair model, undo/redo, named designs, the local staff service, RoomPlan bridge and Unity sources. The "not found on any pushed branch" list in my first entry below is now resolved.

**Done**
- PR #3 restacked from PR #1 onto PR #4 (one force-push of my own branch; previous head `f15d008`).
- Web AR page now uses `tools/generate_demo_models.py` as the single model source, serves sofa and chair by `?sku=`, and rejects unsupported codes. `ar-preview/generate-model.py` removed.
- Review comment posted on PR #4.

**Tested**
- Model pipeline locally: sofa 14 meshes 2.10 ? 1.00 ? 1.03 m, chair 10 meshes 0.84 ? 0.94 ? 0.95 m.
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

## 2026-11-11 � Claude � branch `claude/ar-preview-web` (PR #3)

**Done**
- Branched from `native-live-catalogue` at `d48e80c`; PR #3 is stacked on PR #1.
- `generate-usdz.py`: meshes bound to UsdPreviewSurface materials.
- New `check-usdz.py`: asserts size, floor contact and material bindings.
- `index.html`: Arabic and English, broken characters fixed, WebXR mode added.
- New workflow `ar-preview.yml`: builds GLB and USDZ, uploads the site, deploys to GitHub Pages on `main`.
- Fixes open problems 1 and 2 below once merged and Pages is enabled.

**Tested**
- Scripts run locally; USDZ opens in usd-core, 14 meshes, 2.10 ? 1.00 ? 1.03 m.
- Page text rendered in headless Chrome, both languages.
- Untested on device: AR Quick Look, Scene Viewer, WebXR in a headset browser.

**Not done / known problems**
- No chair page: waiting for Codex's chair model. Codex, when you push it, keep the same script pattern (`generate-model.py` writing `<name>-<code>.glb`) so the page and workflow can take a second product.
- GitHub Pages must be enabled once by Abbas.

**Next**
- Codex: push the chair model and the other unpushed work.
- Claude: add the chair page and a product switcher after that; review PR #1.

---

## 2026-11-11 � Claude � branch `claude/agent-handoff`

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
## YYYY-MM-DD � <agent> � branch `<branch>`

**Done**
- 

**Tested** (how, and on which device; or "untested on device")
- 

**Not done / known problems**
- 

**Next**
- 
```

