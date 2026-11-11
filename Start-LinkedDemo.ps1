param([string]$Adb, [string]$Device, [string]$Apk, [int]$Port = 18766, [switch]$PanelOnly)
$ErrorActionPreference = 'Stop'
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Choose a port between 1024 and 65535.' }
$root = $PSScriptRoot
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python 3 is required.' }
& $python.Source (Join-Path $root 'tools\generate_demo_models.py') --output (Join-Path $root 'generated-models')
if ($LASTEXITCODE) { throw 'Model generation failed.' }
New-Item -ItemType Directory -Force (Join-Path $root 'server\models') | Out-Null
Copy-Item (Join-Path $root 'generated-models\*.mesh.json') (Join-Path $root 'server\models') -Force
$url = "http://127.0.0.1:$Port"
function Health {
    try { return Invoke-RestMethod "$url/api/health" -TimeoutSec 2 -Proxy $null } catch { return $null }
}
$health = Health
if (-not $health) {
    $service = Join-Path $root 'server\showroom_service.py'
    $data = Join-Path $root 'server\data'
    $logs = Join-Path $root 'builds'
    New-Item -ItemType Directory -Force $logs | Out-Null
    $process = Start-Process -FilePath $python.Source -WorkingDirectory $root -ArgumentList @(('"{0}"' -f $service), '--port', "$Port", '--data-dir', ('"{0}"' -f $data)) -PassThru -RedirectStandardOutput (Join-Path $logs 'service.out.log') -RedirectStandardError (Join-Path $logs 'service.err.log')
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 300
        $health = Health
        if ($health) { break }
        if ($process.HasExited) { throw 'Service stopped. Read builds\service.err.log.' }
    }
}
if (-not $health -or $health.application -ne 'almutlaq-showroom' -or $health.protocol -ne 2) {
    throw 'The service is unavailable or another application uses this port. Close the old service or choose -Port 18767.'
}
if ($PanelOnly) { Start-Process $url; Write-Host "Staff panel: $url"; return }
if (-not $Adb) {
    $found = Get-Command adb -ErrorAction SilentlyContinue
    if ($found) { $Adb = $found.Source }
    if (-not $Adb) {
        $Adb = Get-ChildItem "$env:ProgramFiles\Unity\Hub\Editor\*\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $Adb -and $env:LOCALAPPDATA) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate) { $Adb = $candidate }
    }
}
if (-not $Adb -or -not (Test-Path -LiteralPath $Adb)) { throw 'ADB missing. Pass -Adb with its full path, or use -PanelOnly.' }
$devices = @(& $Adb devices | Select-String '^([^\s]+)\s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
if (-not $Device) {
    if ($devices.Count -ne 1) { throw 'Connect one headset and accept USB debugging, or pass -Device SERIAL.' }
    $Device = $devices[0]
}
if ($devices -notcontains $Device) { throw 'The selected device is not authorized or connected.' }
if (-not $Apk) { $Apk = Join-Path $root 'builds\ShowroomVR-Linked.apk' }
if (Test-Path -LiteralPath $Apk) {
    & $Adb -s $Device install -r $Apk
    if ($LASTEXITCODE) { throw 'APK install failed.' }
}
$package = 'com.showroomxr.measuredroom'
$installed = & $Adb -s $Device shell pm path $package
if ($LASTEXITCODE -or -not ($installed -match '^package:')) { throw 'Build-Headset.ps1 must produce the new linked APK first. An older APK uses a different protocol.' }
& $Adb -s $Device reverse tcp:8766 "tcp:$Port"
if ($LASTEXITCODE) { throw 'USB reverse failed. Reconnect the headset.' }
$mapping = & $Adb -s $Device reverse --list
if (-not ($mapping -match "tcp:8766 tcp:$Port")) { throw 'USB mapping was not retained.' }
$bootstrap = Invoke-RestMethod "$url/api/bootstrap" -SessionVariable staff -Proxy $null
$pair = Invoke-RestMethod "$url/api/pairing" -Method Post -WebSession $staff -Headers @{'X-Showroom-CSRF' = $bootstrap.csrf} -ContentType 'application/json' -Body '{}' -Proxy $null
# A fresh launch receives the one-time code. No saved customer data is passed.
& $Adb -s $Device shell am force-stop $package
$activity = (& $Adb -s $Device shell cmd package resolve-activity --brief $package | Select-Object -Last 1).Trim()
if ($activity -notmatch '/') { throw 'Cannot find the headset launch activity.' }
& $Adb -s $Device shell am start -n $activity --es showroom_pair_code $pair.code
if ($LASTEXITCODE) { throw 'Headset launch failed.' }
Start-Process $url
Write-Host "Staff panel: $url"
Write-Host 'Change room width from 4 to 5 m. The panel confirms only after the headset applies it.'
