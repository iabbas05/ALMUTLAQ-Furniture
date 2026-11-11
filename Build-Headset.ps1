param([string]$UnityEditor)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Invoke-UnityBatch {
    param([string[]]$UnityArguments)
    # Windows PowerShell does not consistently wait for GUI executables invoked with &.
    # Quote each argument so project and log paths containing spaces survive Start-Process.
    $quoted = $UnityArguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
    $process = Start-Process -FilePath $UnityEditor -ArgumentList $quoted -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Unity exited with code $($process.ExitCode). Read the requested Unity log." }
}

if (-not $UnityEditor) {
    $UnityEditor = Get-ChildItem "$env:ProgramFiles\Unity\Hub\Editor\*\Editor\Unity.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $UnityEditor -or -not (Test-Path -LiteralPath $UnityEditor)) { throw 'Unity Editor is missing. Pass -UnityEditor with its full path.' }
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python 3 is required.' }
& $python.Source (Join-Path $root 'tools\generate_demo_models.py') --output (Join-Path $root 'generated-models')
if ($LASTEXITCODE) { throw 'Model generation failed.' }
$resources = Join-Path $root 'unity\Assets\Resources\Models'
New-Item -ItemType Directory -Force $resources | Out-Null
Get-ChildItem (Join-Path $root 'generated-models\*.mesh.json') | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $resources ($_.Name.Replace('.mesh.json', '.json'))) -Force
}
$builds = Join-Path $root 'builds'
New-Item -ItemType Directory -Force $builds | Out-Null
$finalApk = Join-Path $builds 'ShowroomVR-Linked.apk'
$env:SHOWROOM_APK_OUTPUT = Join-Path $builds 'ShowroomVR-Linked.pending.apk'
if (Test-Path -LiteralPath $env:SHOWROOM_APK_OUTPUT) { Remove-Item -LiteralPath $env:SHOWROOM_APK_OUTPUT }
$log = Join-Path $builds 'unity-build.log'
# Unity must be closed for this project before batch mode opens it.
$results = Join-Path $builds 'unity-tests.xml'
$testLog = Join-Path $builds 'unity-tests.log'
if (Test-Path -LiteralPath $results) { Remove-Item -LiteralPath $results }
Invoke-UnityBatch -UnityArguments @('-batchmode', '-projectPath', (Join-Path $root 'unity'), '-runTests', '-testPlatform', 'EditMode', '-testResults', $results, '-logFile', $testLog)
if (-not (Test-Path -LiteralPath $results)) { throw "Unity tests did not finish. Read $testLog" }
[xml]$testReport = Get-Content -LiteralPath $results -Raw
if ($testReport.'test-run'.result -ne 'Passed' -or [int]$testReport.'test-run'.passed -lt 1 -or
    [int]$testReport.'test-run'.failed -ne 0) { throw "Unity tests failed or no tests passed. Read $results" }
Invoke-UnityBatch -UnityArguments @('-batchmode', '-quit', '-buildTarget', 'Android', '-projectPath', (Join-Path $root 'unity'), '-executeMethod', 'BuildShowroom.Android', '-logFile', $log)
if (-not (Test-Path -LiteralPath $env:SHOWROOM_APK_OUTPUT) -or
    (Get-Item -LiteralPath $env:SHOWROOM_APK_OUTPUT).Length -eq 0) { throw "Build did not produce a new APK. Open $log" }
Move-Item -LiteralPath $env:SHOWROOM_APK_OUTPUT -Destination $finalApk -Force
Write-Host "Built: $finalApk"

