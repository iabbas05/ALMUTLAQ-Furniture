# Working rules for AI agents

Two agents work in this repository: Codex and Claude. Abbas (repository owner) decides scope and merges.
Read this file and `HANDOFF.md` before starting any task.

## The project

An augmented-reality furniture experience for two Saudi furniture brands, CityW and The Factory.

- **Showroom:** a customer's room layout and size are entered, the customer wears a mixed-reality headset and arranges products at true scale.
- **At home:** a "View in your room" button on the brand websites opens the phone's own AR viewer (AR Quick Look on iPhone, Scene Viewer on Android) with no app install.
- **Shared base:** one 3D model per product, exported as GLB and USDZ, keyed by product code.

Demo products: London three-seater (code `10_14_3`, 210 × 103 × 100 cm) and London chair (code `6_14_5`, 84 × 95 × 94 cm).

## Decided

- The demo uses the London three-seater and London chair.
- Product code is the key that ties a product page, its data and its 3D files together.
- Dimensions come from the official product pages until CAD files arrive.

## Additional decisions already approved by Abbas
- Keep the native Flutter storefront in scope.
- Use Unity for the headset. A full-screen Unity phone experience is the agreed direction, but it is not integrated yet.
- Headset: PICO 4 Ultra. Demo location: Bahrain.
- Customer designs are saved with name and phone only after customer permission. Keep identity in the local staff database, never in the headset scene or the public repository.
- Add an iOS RoomPlan scan option on supported LiDAR hardware with a review step. Manual measurements remain available.
- Follow the existing approval for complete implementation and testing. Do not repeat decisions above as open questions.

## Open dependencies
- Approved product geometry/CAD, visual and fabric approval, complete catalogue/API coverage, stock and checkout access.
- Company distribution/signing accounts and applicable Unity industry licensing.
- On-device measurements, tracking, memory and performance acceptance.

## Branches and pull requests

- Codex works on `codex/<topic>` branches (the existing `native-live-catalogue` branch counts as Codex's).
- Claude works on `claude/<topic>` branches.
- Never commit to another agent's branch, and never push directly to `main`.
- Every change reaches `main` through a pull request. The other agent reviews it; Abbas merges.

## Definition of done

Work is "done" only when all of these are true:

1. It is pushed to the branch, not only on a local machine.
2. GitHub Actions passes on that branch, or the failure is written in `HANDOFF.md`.
3. `HANDOFF.md` is updated.

Anything not yet tested on a real phone or headset is labelled "untested on device".

## Public repository

This repository is public. Never commit client names, email addresses, phone numbers, prices quoted to the client, customer data, API keys or signing credentials.

## Code notes

- Save every file as UTF-8. Arabic text must survive a round trip.
- Keep generated 3D files reproducible from `tools/generate_demo_models.py`, with USDZ export under `ar-preview/`.
- Measure models against the published dimensions in a test, as `test/room_planner_test.dart` does.

## Ownership for this work session
- Codex: Flutter, room contract, local staff service, native iOS RoomPlan bridge, headset Unity source, build verification.
- Claude: website AR page and hosting, USDZ delivery, proposal content, independent review.
- Codex's new generator is tools/generate_demo_models.py. Do not overwrite the website generator on another agent's branch. Agree the shared model outputs through HANDOFF.md.
- Use synthetic TEST records in tests. Device acknowledgements only mean the specified scene revision was actually applied.
- The local service is loopback-only. It is a demo, not a production account/permission system.

## Coordination update, 2026-11-11
- Claude's ordered review tasks are in PR #4 comments 6790747625 and 6790882987.
- Resolve shared-document differences on the Codex branch without rewriting Claude's history or main. The current conversation explicitly confirms PICO 4 Ultra, Bahrain, Flutter and customer saves. Those decisions supersede the older open questions in PR #2.
- Customer retention defaults to 30 days in this demo, configurable from 1 to 365 days. Expired records are removed on service start or policy update. Single-record export is staff-only. Real showroom policy remains a company deployment dependency.
- Web AR uses the build-time URL, selected SKU and language. Never substitute another product for an unsupported SKU.
- The Unity headset dependency is pinned to the official PICO SDK because Abbas already specified PICO 4 Ultra in this conversation. Real Unity/PICO compilation and tests remain mandatory, not implied by mobile CI.
