# Build and test

This is a native Flutter storefront with a measured Flutter room preview, a separate Unity headset project, a local staff service, and a web AR page. It is not a complete ERP/payment integration.

## Mobile artifacts

GitHub Actions > Build Almutlaq mobile apps builds an Android debug APK and an unsigned iOS IPA, plus a signed IPA when signing secrets are set (below). Each build generates the GLBs and USDZs from tools/generate_demo_models.py: London sofa and chair (room planner, headset and phone AR) and the CityW Warm Beige three-seater `23_88_1` (phone 3D/AR only). The list of products with phone AR lives in `lib/product_ar.dart`. iPhone product preview opens the bundled USDZ using native AR Quick Look at fixed scale. RoomPlan requires supported LiDAR hardware. Android camera AR needs the published HTTPS AR page URL passed as SHOWROOM_AR_URL (workflow input ar_url). No AR host is hardcoded before deployment.

Actions artifacts include Almutlaq-Android-APK, Almutlaq-Unsigned-IPA, Almutlaq-App-Screenshots and Almutlaq-Staff-Previews. Open the complete workflow run summary to download artifacts, rather than a single job page. The unsigned IPA requires signing before normal iPhone installation. Debug Android is for testing, not a store release.

## Signed iPhone build

The unsigned IPA cannot be installed on an iPhone. To get an installable one, add three repository secrets (Settings > Secrets and variables > Actions). Never commit these files or values; this repository is public.

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | Apple Distribution certificate with its private key, exported from Keychain as .p12, then `base64 -i cert.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password chosen when exporting the .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision` |

The bundle ID is read from the profile (`com.showroomxr.londonShowroom` when the profile uses a wildcard App ID). The export method follows the profile: Ad Hoc profiles produce `release-testing` IPAs for the registered devices, App Store profiles produce an App Store Connect upload, Enterprise profiles an in-house build. The job then uploads Almutlaq-Signed-IPA. Without the secrets these steps are skipped. Untested until real signing material is added.

## Headset on Windows

Use Unity Editor 6000.6.8f1 with Android Build Support, SDK, NDK and OpenJDK, an activated compatible Unity licence, Git and Python 3. Close this Unity project before the batch build. The PICO Integration SDK is pinned to official commit c93a59b.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Headset.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-LinkedDemo.ps1
```

The build produces builds/ShowroomVR-Linked.apk, package com.showroomxr.measuredroom. Logs are in builds/. The launcher uses the new protocol-v2 APK, not the earlier room-only APK. It discovers the connected device, verifies the USB mapping from headset 8766 to PC 18766, and opens the staff panel. If multiple devices are connected, pass -Device SERIAL. A custom Unity path uses -UnityEditor on the build script. A custom ADB path uses -Adb on the launcher. To open the panel without a headset, use -PanelOnly. Customer data stays in server/data on the PC.

## Acceptance

1. Change width from 4 to 5 m. Confirm the headset revision matches the panel and the sofa remains 2.10 m wide.
2. Add the London chair, move/rotate both pieces, verify room boundaries and clearances against a real measurement.
3. Add/remove door and window openings. Check orientation in 2D and 3D.
4. Save a synthetic TEST customer with consent, start a new session, restore the saved room and confirm no identity is sent to the headset.
5. Disconnect USB, edit on the PC, reconnect and relaunch. Only a fresh applied scene confirms the new revision.
6. Preview/upload/publish a dimension-matching static GLB. Confirm the open scene retains its immutable prior version until explicitly replaced.
7. Test Arabic/English and large text on physical Android/iPhone. Check offline catalogue fallback and the native iPhone preview.

All physical acceptance remains pending until observed on real devices. Reconstructed London geometry requires manufacturer visual approval.

## Website AR

The AR workflow packages the SKU-aware page plus every generated GLB/USDZ pair as ar-preview-site. Publishing is reserved for main and requires GitHub Pages configured by the owner. Development artifacts do not establish that the website is live.
