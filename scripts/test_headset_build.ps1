$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('almutlaq build test ' + [guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') -Force | Out-Null
Copy-Item (Join-Path $repo 'Build-Headset.ps1') $fixture
Copy-Item (Join-Path $repo 'tools/generate_demo_models.py') (Join-Path $fixture 'tools')
$originalOutput = $env:SHOWROOM_APK_OUTPUT
$fixtureState = @{ scenario = ""; buildCalled = $false }
# Substitute only the external Unity process. Exercise the real build script and model generator.
function Start-Process {
    param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, [switch]$Wait)
    if ($fixtureState.scenario -eq 'prepare-only') { throw 'Prepare-only launched Unity.' }
    if (-not $Wait -or -not $PassThru -or $WindowStyle -ne 'Hidden') { throw 'Unity launch must wait and stay hidden.' }
    $argsList = @($ArgumentList | ForEach-Object { $_.Trim('"') })
    $project = $argsList[[Array]::IndexOf($argsList, '-projectPath') + 1]
    if ($project -ne (Join-Path $fixture 'unity')) { throw 'Project path with spaces was damaged.' }
    if ($argsList -contains '-runTests') {
        if ($fixtureState.scenario -eq 'process-failure') { return [pscustomobject]@{ExitCode = 9} }
        $report = $argsList[[Array]::IndexOf($argsList, '-testResults') + 1]
        if ($fixtureState.scenario -ne 'missing-report') {
            $passed = if ($fixtureState.scenario -eq 'zero-tests') { 0 } else { 2 }
            $result = if ($fixtureState.scenario -eq 'failed-tests') { 'Failed' } else { 'Passed' }
            [IO.File]::WriteAllText($report, "<test-run result='$result' passed='$passed' failed='0' />")
        }
    } else {
        $fixtureState.buildCalled = $true
        if ($fixtureState.scenario -ne 'missing-apk') {
            $payload = if ($fixtureState.scenario -eq 'empty-apk') { '' } else { 'NEW TEST APK' }
            [IO.File]::WriteAllText($env:SHOWROOM_APK_OUTPUT, $payload)
        }
    }
    return [pscustomobject]@{ExitCode = 0}
}
try {
    $fixtureState.scenario = 'prepare-only'
    & (Join-Path $fixture 'Build-Headset.ps1') -UnityEditor (Join-Path $fixture 'missing-editor.exe') -PrepareOnly | Out-Null
    foreach ($sku in @('10_14_3','6_14_5')) {
        if (-not (Test-Path -LiteralPath (Join-Path $fixture "unity/Assets/Resources/Models/london-$sku.json"))) { throw 'Prepare-only did not create both model resources.' }
    }
    Write-Host 'PASS: prepare-only without a Unity installation'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'builds') -Force | Out-Null
    $apk = Join-Path $fixture 'builds/ShowroomVR-Linked.apk'
    foreach ($case in @('process-failure', 'missing-report', 'zero-tests', 'failed-tests', 'missing-apk', 'empty-apk', 'success')) {
        $fixtureState.scenario = $case
        $fixtureState.buildCalled = $false
        [IO.File]::WriteAllText($apk, 'OLD TEST APK')
        # Neither a stale report nor a stale temporary APK should count as a new result.
        [IO.File]::WriteAllText((Join-Path $fixture 'builds/unity-tests.xml'), "<test-run result='Passed' passed='2' failed='0' />")
        [IO.File]::WriteAllText((Join-Path $fixture 'builds/ShowroomVR-Linked.pending.apk'), 'STALE TEST APK')
        $failure = $null
        try { & (Join-Path $fixture 'Build-Headset.ps1') -UnityEditor (Get-Command powershell.exe).Source | Out-Null }
        catch { $failure = $_ }
        if ($case -eq 'success') {
            if ($failure) { throw $failure }
            if ([IO.File]::ReadAllText($apk) -ne 'NEW TEST APK') { throw 'Successful build was not promoted.' }
        } else {
            if (-not $failure) { throw "Expected failure: $case" }
            if ([IO.File]::ReadAllText($apk) -ne 'OLD TEST APK') { throw "Previous APK lost: $case" }
            if ($case -in @('process-failure','missing-report','zero-tests','failed-tests') -and $fixtureState.buildCalled) { throw 'Build ran before tests passed.' }
        }
        Write-Host "PASS: $case"
    }
} finally {
    $env:SHOWROOM_APK_OUTPUT = $originalOutput
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notlike 'almutlaq build test *') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
