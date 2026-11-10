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

## Open (do not decide alone; ask Abbas)

- Whether the Flutter app stays in scope, or the demo focuses on the web AR page plus a headset app.
- Whether Unity is used only for the headset app or also inside the phone app.
- Headset model, demo location, and whether customer name and phone are stored (personal data rules apply).

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
- Keep generated 3D files reproducible from the scripts in `ar-preview/`.
- Measure models against the published dimensions in a test, as `test/room_planner_test.dart` does.
