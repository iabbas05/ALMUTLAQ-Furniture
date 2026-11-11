# Delivery status and blocked steps

Updated 2026-11-11. This is a development checkpoint, not a claim that the complete product is finished. Earlier elapsed-time estimates did not account for a successful licensed Unity build and should not be treated as delivery commitments.

## Verified outputs

| Output | Evidence | Limits |
| --- | --- | --- |
| Flutter Android APK | Completed workflow 43009850101, code 15e0c55 | Debug build; no physical phone acceptance |
| Flutter iOS IPA | Same completed workflow | Unsigned; requires signing before normal iPhone installation |
| Staff service and browser | Protocol/HTTP/storage/browser CI passed in the same run | Demo loopback/USB service, not production authentication |
| Windows launcher | Windows job passed | Simulated process paths and repeat-start persistence; no real USB acceptance |
| Shared sofa/chair models | CI model generation and USDZ checks passed | Reconstructed geometry, not approved CAD/textures |
| Headset runtime C# | Editor and Android conditional compilation against installed Unity reference assemblies passed | Excludes asmdef resolution, Editor scripts, PICO SDK, IL2CPP and APK |
| Build safeguards | Eight simulated process/build scenarios pass locally | Does not invoke real Unity |
| Customer storage | Fifteen local storage tests pass | Synthetic records only; HTTP integration validated separately in CI |

Downloads and logs: https://github.com/iabbas05/ALMUTLAQ-Furniture/actions/runs/43009850101

The newest build-script/menu changes need their own CI result. CI mobile jobs do not compile Unity Editor scripts or produce a PICO APK.

## Written but not validated in Unity

- PICO Android scene/build configuration and pinned SDK import.
- Rejected-scene edit-mode tests.
- Almutlaq > Test and build PICO APK menu, including showroom-assembly/run matching, startup-error handling, nonzero passed-test gate and fresh pending-output promotion.
- Actual headset networking, controls, model rendering and dimensional acceptance.

The most recent full Editor attempt ended in a crash after licensing IPC, Burst named-pipe and Mono socket initialization failures. There is no fresh headset APK and no successful Unity test report. The desktop UI inventory showed Hub, not an Editor project. No licence bypass or reduction of environment protections was attempted.

## Steps requiring the normal Windows desktop

### 1. Prepare the project without launching Unity

Use the current Codex branch. If working in an existing Git checkout, save/commit your own work before updating it. Do not reset or overwrite another working copy. A new checkout avoids conflicts:

```powershell
git clone --branch codex/unified-room-v08 --single-branch https://github.com/iabbas05/ALMUTLAQ-Furniture.git ALMUTLAQ-PICO
Set-Location ALMUTLAQ-PICO
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Headset.ps1 -PrepareOnly
```

Expected: both model JSON resources under unity/Assets/Resources/Models. This does not start Unity, ADB or an installation. Python 3 and Git are prerequisites.

### 2. Compile, test and build inside Unity

1. In Unity Hub add the checkout's unity folder as a project. Open with 6000.6.8f1 with Android Build Support, SDK/NDK/OpenJDK installed.
2. If Hub asks, complete normal account sign-in and compatible licence activation. Wait for package import. Resolve Console errors before proceeding. An open Hub window alone is not an open Editor project.
3. In File > Build Profiles choose Android and switch the active platform. Finish switching before starting tests.
4. Select Almutlaq > Test and build PICO APK. Save modified scenes if asked. No headset needs to be connected.
5. Expected: builds/unity-editor-tests.xml shows passed tests, then a newly generated nonempty builds/ShowroomVR-Linked.apk. A test-start error, failed/no tests or build failure must stop the process and retain the previous final APK.
6. If this fails, retain the Console error text, test XML and Editor log. Do not label the build successful or clear licensing/security settings to force it.

Alternative after closing this project in Editor:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Headset.ps1
```

Expected batch report: builds/unity-tests.xml. Batch logs: builds/unity-tests.log and builds/unity-build.log.

### 3. Install and validate later, when the headset is available

Enable PICO developer mode/USB debugging, connect a data-capable cable and accept the debugging prompt inside the headset. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-LinkedDemo.ps1
```

Follow docs/DEVICE_TESTS.md. Measure both furniture sizes, change room width 4 to 5 m, verify revision acknowledgement, disconnect/reconnect, save/restore a TEST design, and record tracking drift/frame rate. These require physical observations and cannot be inferred from an APK existing.

## External dependencies and implementation still outstanding

| Item | Required action or remaining work |
| --- | --- |
| Web AR hosting | After PR #4 is ready and merged by Abbas, enable Settings > Pages > Source: GitHub Actions; verify the printed deployed URL and both products; pass that real URL as ar_url when rebuilding Android |
| iPhone installation | Company/user Apple signing credentials and a compatible device; validate native Quick Look and RoomPlan on hardware |
| Product assets | Manufacturer CAD or visual/fabric approval, plus production textured-model import work |
| Full catalogue/commerce | Verify catalogue coverage, approved stock/price/order APIs, accounts, payments and ERP requirements; these are not completed by the current local basket |
| Phone Unity embedding | Still needs implementation and lifecycle/message/memory/device tests after the first headset pass |
| Passthrough | Separate unimplemented scope. Current showroom is a rendered room from entered dimensions, without a camera passthrough view |
| Production deployment | Replace/approve demo transport and pairing/account design, confirm retention and signing/distribution, then venue acceptance |

These are a mixture of account/device dependencies and unfinished engineering work. They are not all tasks the owner completes by clicking settings. The executable roadmap and Codex/Claude responsibilities are in docs/EXECUTION_PLAN.md. PR #4 stays a draft while its stated build/device acceptance gates remain open.
