# USB showroom demo

## Build from an already-open Unity Editor

No connected headset is required to build. Open this repository's `unity/` project with Unity 6000.6.8f1 and wait for package import and compilation. In File > Build Profiles select Android and switch the active platform. Use Almutlaq > Test and build PICO APK.

The menu offers to save modified scenes, runs only Almutlaq.Showroom.Tests in Edit Mode, writes builds/unity-editor-tests.xml, and builds only after at least one test passes with no failures. It writes a fresh pending APK before promoting it to builds/ShowroomVR-Linked.apk. The existing APK survives a failed build. The menu is a new unverified Editor integration until run in a working licensed Editor; runtime-source compilation does not validate it.

This path uses the Editor already open on the desktop rather than launching another batch-mode process. It still requires a working Unity licence, resolved PICO packages and Android support. If model resources are missing, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Headset.ps1 -PrepareOnly` before opening the project. PrepareOnly generates/copies both models without launching Unity or using ADB. No auto-build occurs just by opening the project.

## First device run: actions at the Windows desktop

The automated session crashed in Unity licensing IPC/Burst and Mono socket startup, and could not start the ADB daemon. This does not prove that the installed licence is invalid or that the headset is disconnected. Complete this first run from your normal Windows desktop.

1. Open Unity Hub, sign in if requested, and check Licenses for an activated licence suitable for your organisation. Open this repository's `unity/` project with Editor 6000.6.8f1. Let the pinned packages finish importing. Resolve Console errors first, then close the project so batch mode can open it.
2. Open Windows PowerShell in the repository root and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Headset.ps1
   ```

   Expected: at least one Unity edit-mode test passes, then a fresh `builds/ShowroomVR-Linked.apk` is produced. Read `builds/unity-tests.log` and `builds/unity-tests.xml` if the test phase fails, or `builds/unity-build.log` if the Android build fails. An old APK is preserved on failure and does not count as a new build.
3. Power on the PICO 4 Ultra, enable USB debugging in developer settings, connect a data-capable USB cable and accept the USB debugging prompt inside the headset. Run:

   ```powershell
   $picoAdb = Join-Path $env:ProgramFiles 'Unity\Hub\Editor\6000.6.8f1\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe'
   & $picoAdb start-server
   & $picoAdb devices -l
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-LinkedDemo.ps1 -Adb $picoAdb
   ```

   Expected: one device listed as `device`, successful APK installation, a staff panel address and the headset app opening. `unauthorized` requires accepting the prompt inside the headset. A daemon failure must be resolved before pairing. With multiple devices pass `-Device SERIAL` to the launcher.
4. Change room width from 4 to 5 metres and wait for the headset to display that revision. Record the observed result in `docs/DEVICE_TESTS.md`. Mobile CI and simulated acknowledgements do not complete this device check.

The one-time pairing code is sent as an Android launch extra and may be visible in device diagnostic logs. This USB demo mechanism is not a production sign-in system. Avoid sharing raw device logs while a pairing code is valid.

Android phone camera AR also needs a deployed HTTPS AR page. Do not infer hosting from a successful AR packaging workflow. After GitHub Pages is enabled and the deployed address verified, record the address in HANDOFF.md and provide it as the mobile workflow's `ar_url` input.

This runbook targets Windows and PICO 4 Ultra. It is a test build, not a production deployment.

1. Install Unity 6000.6.8f1 with Android Build Support, SDK/NDK/OpenJDK, Git and Python 3. Activate the applicable Unity licence. Expected: Unity opens the project under `unity/` and resolves the pinned PICO package. If package import fails, read the Unity Console before building.
2. Close the project in Unity. In PowerShell at the repository root, run `./Build-Headset.ps1`. Expected: `builds/ShowroomVR-Linked.apk` and `builds/unity-build.log`. If Unity was installed elsewhere, pass `-UnityEditor 'FULL_PATH_TO_Unity.exe'`. A successful mobile Actions run does not build this separate APK.
3. Enable developer mode and USB debugging on the PICO. Connect USB and accept the debugging prompt inside the headset. Expected: `adb devices -l` lists the headset as `device`. For `unauthorized`, accept the prompt. For no device, check cable and developer mode.
4. Run `./Start-LinkedDemo.ps1`. Expected: the service opens at `http://127.0.0.1:18766`, an APK install succeeds if the APK is present, and the headset app launches with a one-use pairing code. The launcher verifies reverse `tcp:8766 tcp:18766`. It does not assume a device serial. Use `-Device SERIAL` only for multiple devices.
5. If port 18766 is occupied by an old service, close its window or use `-Port 18767`. Expected: the PC URL changes but the headset endpoint remains 8766 through USB reverse. If ADB is outside the discovered paths, pass `-Adb 'FULL_PATH_TO_adb.exe'`.
6. Enter width 5, depth 5, height 2.8 and press the send button. Expected: pending status first, then the same revision on the PICO and a fresh confirmation on the staff panel. A connection or HTTP success alone is not an applied scene.
7. Add a London chair. Move/rotate it using the PC plan or headset sticks. Expected: chair 0.84 x 0.95 x 0.94 m, sofa 2.10 x 1.03 x 1.00 m, unchanged by room resizing. Whole rotated footprints remain inside the room. Add/remove a door or window and open the staff 3D cutaway to compare.
8. Save a synthetic `TEST CUSTOMER`, number `00000000`, with permission checked. Start a new session and restore that record. Expected: design returns, gets a new session ID, and waits for headset confirmation. Names/numbers appear only in the local staff database and explicit export.
9. Close/reopen the launcher. Expected: the same saved customer remains, the service uses the same `server/data` directory, and a fresh device acknowledgement confirms the room. The default retention is 30 days, configurable in saved experiments. Older records are removed at service start or policy change. Exported files and backups need separate handling.
10. Unplug USB. Expected: the visible headset scene is retained and the panel stops reporting a recent device reply. Reconnect and rerun the launcher to recreate reverse and restart pairing if required. Do not reinstall or clear application data as the first diagnostic step.

The launcher also supports `-PanelOnly` to run the staff UI without a headset. Browser tests use simulated ACKs. Real measurement, tracking and performance evidence belongs in DEVICE_TESTS.md.

