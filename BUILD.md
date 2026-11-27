# Build and test

This is a native Flutter storefront with a measured Flutter room preview, a separate Unity headset project, a local staff service, and a web AR page. It is not a complete ERP/payment integration.

## Mobile artifacts

GitHub Actions > Build Almutlaq mobile apps builds an Android debug APK and an unsigned iOS IPA. Each build generates the London sofa/chair GLBs and USDZs from tools/generate_demo_models.py. iPhone product preview opens the bundled USDZ using native AR Quick Look at fixed scale. RoomPlan requires supported LiDAR hardware. Android camera AR needs the published HTTPS AR page URL passed as SHOWROOM_AR_URL (workflow input ar_url). No AR host is hardcoded before deployment.

Actions artifacts include Almutlaq-Android-APK, Almutlaq-Unsigned-IPA, Almutlaq-App-Screenshots and Almutlaq-Staff-Previews. Open the complete workflow run summary to download artifacts, rather than a single job page. The unsigned IPA requires signing before normal iPhone installation. Debug Android is for testing, not a store release.

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

The AR workflow packages the SKU-aware page plus both GLB/USDZ pairs as ar-preview-site. Publishing is reserved for main and requires GitHub Pages configured by the owner. Development artifacts do not establish that the website is live.
