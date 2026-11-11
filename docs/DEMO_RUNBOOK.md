# USB showroom demo

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
