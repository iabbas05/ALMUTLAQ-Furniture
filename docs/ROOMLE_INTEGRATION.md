# Roomle Room Designer and AR

This optional integration opens Roomle's hosted planner or a mapped product in the phone's external browser. It is not embedded Unity, a native PICO integration, or a bidirectional room synchronisation. The existing measured planner, native iOS Quick Look, hosted Android AR and headset protocol remain available.

## Account setup

An activated Roomle account and permitted catalogue are required. Enable Room Designer (`moc`) in Rubens Admin, set up the product catalogue and its root tag, and obtain the account's configurator ID. This repository has no Roomle subscription, credentials or verified catalogue. Do not substitute Roomle's sample furniture for Almutlaq products.

Set these public GitHub Actions repository variables for Android and unsigned iOS builds:

| Variable | Value |
| --- | --- |
| `ROOMLE_CONFIGURATOR_ID` | Configurator ID issued by Roomle |
| `ROOMLE_CATALOG_ROOT_TAG` | Root tag for the permitted furniture catalogue |
| `ROOMLE_PRODUCT_IDS` | JSON object mapping exact Almutlaq SKU to the corresponding Roomle item ID |

For example, the JSON shape is `{"10_14_3":"YOUR_CATALOG:YOUR_SOFA_ITEM","6_14_5":"YOUR_CATALOG:YOUR_CHAIR_ITEM"}`. Replace these placeholders with verified identifiers before configuring a build. These values ship in the application and must never contain secrets or customer data.

The planner button appears on the Room page only with both configurator and catalogue identifiers. Product pages show the separate Roomle product/AR button only for explicitly mapped SKUs. The hosted product viewer offers AR according to the account and phone capabilities. Launching this page does not automatically start the camera. No missing SKU falls back to another product.

Roomle opens with no customer name, phone, pairing code, room dimensions or local design. The Room page explains that its design is separate. Roomle's own save/account behaviour is governed by that service. Saving to the local staff database and sending a scene to PICO still use the existing local planner.

## Local builds

Set the same environment variables locally, then run `python scripts/prepare_roomle.py`. Build with `flutter build apk --debug --dart-define-from-file=build/roomle-defines.json` or the equivalent iOS command. Add `SHOWROOM_AR_URL` separately for the existing hosted phone AR. Empty Roomle variables disable the optional integration. Invalid JSON or incomplete account configuration stops CI preparation with an explicit error.

## Acceptance still required

- Confirm exact sofa/chair mappings, real dimensions and approved appearance in Roomle.
- Open the planner and each mapped product on iOS and Android. Verify unsupported products have no Roomle button.
- Check the real account's AR entitlement and both phones' camera/tracking behaviour.
- Verify local saved rooms are unchanged after browser return and launch failure.
- Plan a separately reviewed scene conversion before promising transfer of Roomle layouts to PICO. No import/export mapping is implemented here.

Untested with a real Roomle tenant and untested on device. This adapter is preparation, not a deployed commercial Roomle experience.

## Official references

- https://docs.roomle.com/rubens/rubens-products/rubens-room-designer/integration/setup-room-designer
- https://docs.roomle.com/rubens/rubens-products/rubens-room-designer/getting-started
- https://docs.roomle.com/rubens/rubens-products/rubens-3d-viewer-and-ar/getting-started
