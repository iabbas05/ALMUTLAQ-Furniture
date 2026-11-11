# Implementation and review plan
Updated 2026-11-11. Proposed by Codex for Claude review at Abbas's request.

## Goal and recommended sequence
Deliver a reproducible PICO 4 Ultra showroom demonstration first. Build without a connected headset; reserve installation, tracking, scale and performance acceptance for the device session. Keep the existing native Flutter catalogue and the shared metre-based room contract. Use the same versioned GLB/USDZ/mesh outputs for both London products. Do not expand commercial features before the first device pass.

This is a sequencing recommendation. Claude has not yet reviewed this document. Existing device choice and scope were explicitly confirmed by Abbas and are not open questions.

## Evidence and current limits
- Code checkpoint 8139f1d: mobile workflow 43003769899 passed Windows launch persistence, seven simulated Unity build cases, protocol/storage/HTTP/browser checks, Flutter analysis/tests, Android APK and unsigned iOS IPA.
- AR packaging workflow 43003769966 passed. Packaging does not establish HTTPS hosting.
- Documentation continuation 104b479 records the verified artifacts and desktop runbook.
- Local Unity attempt crashed during licence IPC, Burst named-pipe and Mono socket initialization. ADB daemon startup also failed in this automated session. This does not establish a defective licence or disconnected headset.
- Runtime C# compilation against installed Unity reference assemblies is an additional source check. It excludes PICO SDK/editor code, Unity tests, IL2CPP and APK generation.
- No physical acceptance for PICO, iPhone AR, Android AR or RoomPlan. Production geometry, full catalogue, stock/ERP/payments and distribution are not complete.

## Recommended architecture
| Area | Decision | Reason |
| --- | --- | --- |
| Showroom | Dedicated Unity ARM64 Android APK on PICO 4 Ultra | Reuse existing room consumer and avoid tying the first demo to phone embedding |
| Staff control | Loopback Python/SQLite service, browser panel, USB reverse | Existing tested path, local customer saves and explicit revision acknowledgement |
| Product assets | One generator and immutable model versions, common metre units | Same dimensions and triangles across staff preview, headset and phone/web exports |
| Phone now | Native Flutter storefront and measured plan; native iPhone Quick Look; hosted web AR for Android when deployed | Existing working build with separate device acceptance |
| Phone later | Full-screen Unity experience after headset validation | Isolate renderer/platform integration from the first showroom acceptance |
| Commerce later | Approved catalogue/stock/checkout adapters | Avoid treating fallback catalogue and local basket as verified live commerce |

PICO SDK remains pinned to the current official source commit. Do not switch headset/vendor dependencies before comparing actual compile and device evidence. Claude should correct any older proposal naming a different headset.

## Stages and completion gates
| Priority | Work | Owner | Depends on | Required evidence |
| --- | --- | --- | --- | --- |
| P0 | Verify downloadable IPA/APK and record exact workflow | Codex | Existing CI | Completed; artifact IDs in HANDOFF |
| P1 | Run Test-HeadsetSource.ps1 for Editor and Android conditional source | Codex | Installed Editor references and .NET SDK | Both compilations pass; limits shown in output |
| P1 | Resolve full Unity execution environment and build without headset | Codex, with Claude review | Working licensed Editor, package/network/IPC access, Android modules | PICO SDK import, editor compile, nonempty passed edit-mode test report, fresh ARM64 APK and build log |
| P1 | Independently review Unity build/loader and launch flow | Claude | Current branch | Specific findings with file/line and reproduction; no claim of physical validation |
| P2 | First physical PICO pass | Codex with Abbas at headset | Fresh APK, powered headset and USB debugging acceptance | DEVICE_TESTS checklist with observed values and logs |
| P2 | Publish and verify HTTPS AR site | Claude | Owner-accessible Pages configuration and approved publication branch | Live URL serves correct sofa/chair assets, unknown SKU handled, native phone checks |
| P2 | Rebuild Android with verified AR URL | Codex | Actual deployed HTTPS address | Recorded input plus fresh APK, correct SKU/language target |
| P3 | Phone Unity integration prototype | Codex, Claude review | First headset pass | Separate integration branch; model/room exchange, lifecycle, memory and return navigation checks on real devices |
| P3 | RoomPlan and native iPhone validation | Codex | Supported signed device build | Review-before-apply, reject unsupported/nonrectangular auto-replacement, correct scale |
| P4 | Production asset/catalogue and commercial integrations | Split after interface review | CAD/material approval, company APIs/accounts and requirements | SKU reconciliation, dimension/texture validation, live stock/price/order contract tests |
| P5 | Release and venue acceptance | Abbas/company with implementation support | Prior gates and signing/distribution | Signed builds, configured deployment, support/retention policy and approved pilot results |

No fixed completion date until a real Unity build attempt reaches compilation and its dependency errors are known. Separate time for engineering from time waiting for account access, asset approval and hardware.

## Work while Abbas is away
1. Complete source checks and static review without touching the headset.
2. Reproduce geometry generation and cross-format dimension checks.
3. Keep launcher/build safeguards, logs and desktop instructions reviewable.
4. Claude reviews the pinned PICO loader/build APIs, shader inclusion, Android settings, model loading and scene ACK rules.
5. Prepare hosting configuration and verify deployment prerequisites without inventing a URL.
6. Plan phone Unity lifecycle/message boundaries, but avoid implementing new product features before first device evidence.

Full Unity compilation still needs a working execution environment and licence. A connected headset is not required for it. Do not bypass sandbox restrictions or treat source compilation as an APK.

## First physical pass
Use docs/DEMO_RUNBOOK.md and record results in docs/DEVICE_TESTS.md:
- Width 4 to 5 metres changes room dimensions without scaling the sofa/chair.
- Both products match the published dimensions using a tape measure.
- Move/rotate keeps the complete footprints inside the room.
- Invalid scene or missing model retains the previous scene and does not acknowledge the rejected revision.
- Restart/disconnect/reconnect requires a fresh applied-revision acknowledgement.
- Tracking/drift after five minutes and measured frame rate are recorded, not inferred.
- Save/restore a synthetic TEST design and verify identity never enters the headset document.
- Device failure blocks release claims even when mobile CI passes.

## Claude review request
Please reply on PR #4 with:
1. Accept or revise the recommended sequence and architecture table.
2. Review the source-check limitations and full PICO build path. Suggest a licensed CI route only if the required runner, Editor version and credentials exist; never put licence data in the public repo.
3. Check the runbook's manual desktop steps and the pairing-code demo limitation.
4. Reconcile proposal headset wording to PICO 4 Ultra and list any remaining contradictory statements.
5. For Pages, report actual deployment capability/status and the verified address, or the specific owner action still required.
6. List blockers by priority with ownership and evidence needed to close them.

## Coordination and scope
Codex writes only codex/ branches; Claude writes only claude/ branches. Review through PRs and HANDOFF. No direct pushes to main or rewriting the other agent's branch. Merge remains with Abbas under AGENTS.md. PR #4 stays draft until its stated acceptance limits are resolved. Private customer data, credentials and client commercial details stay out of the public repository.

Any reviewer recommendation is proposed until supported by tests and recorded. Report what was written, built and physically observed separately.
