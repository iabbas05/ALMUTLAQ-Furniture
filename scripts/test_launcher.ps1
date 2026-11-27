$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($file in @('Start-LinkedDemo.ps1', 'Build-Headset.ps1')) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw ($errors | Out-String) }
}
$port = 18768
$data = Join-Path ([System.IO.Path]::GetTempPath()) ('almutlaq-test-' + [guid]::NewGuid())
$pidFile = Join-Path $root "builds/service-$port.pid"
$url = "http://127.0.0.1:$port"
try {
    & (Join-Path $root 'Start-LinkedDemo.ps1') -PanelOnly -NoBrowser -Port $port -DataDirectory $data
    $bootstrap = Invoke-RestMethod "$url/api/bootstrap" -SessionVariable staff -Proxy $null
    $headers = @{'X-Showroom-CSRF' = $bootstrap.csrf}
    $record = Invoke-RestMethod "$url/api/customers" -WebSession $staff -Method Post -Headers $headers -ContentType 'application/json' -Body '{"name":"TEST CUSTOMER","phone":"00000000","consent":true}' -Proxy $null
    & (Join-Path $root 'Start-LinkedDemo.ps1') -PanelOnly -NoBrowser -Port $port -DataDirectory $data
    $rows = Invoke-RestMethod "$url/api/customers?q=TEST" -WebSession $staff -Proxy $null
    if ($rows.customers.Count -ne 1 -or $rows.customers[0].id -ne $record.id) { throw 'Second launcher run lost the saved design.' }
    Write-Host 'Launcher startup and repeated-run persistence passed on Windows. USB/device path not tested.'
} finally {
    if (Test-Path -LiteralPath $pidFile) {
        $servicePid = [int](Get-Content -LiteralPath $pidFile)
        Stop-Process -Id $servicePid -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $pidFile -Force
    }
    if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
}
