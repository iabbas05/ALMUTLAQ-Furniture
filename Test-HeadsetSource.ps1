param([string]$UnityEditor, [string]$Compiler)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $UnityEditor) { $UnityEditor = Join-Path $env:ProgramFiles 'Unity\Hub\Editor\6000.6.8f1\Editor\Unity.exe' }
$unityData = Join-Path (Split-Path $UnityEditor -Parent) 'Data'
$dotnet = (Get-Command dotnet -ErrorAction Stop).Source
if (-not $Compiler) {
    $Compiler = Get-ChildItem (Join-Path (Split-Path $dotnet -Parent) 'sdk\*\Roslyn\bincore\csc.dll') |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) { throw 'Install a .NET SDK or pass -Compiler with the full csc.dll path.' }
$references = @(Get-ChildItem (Join-Path $unityData 'NetStandard\ref\2.1.0\*.dll')) +
    @(Get-ChildItem (Join-Path $unityData 'Managed\UnityEngine\*.dll'))
if ($references.Count -lt 2) { throw 'Unity reference assemblies are missing.' }
$output = Join-Path $root 'builds\source-check'
New-Item -ItemType Directory -Force $output | Out-Null
foreach ($target in @('Editor', 'Android')) {
    $defines = if ($target -eq 'Editor') { 'UNITY_EDITOR,UNITY_6000_0_OR_NEWER' } else { 'UNITY_ANDROID,UNITY_6000_0_OR_NEWER' }
    $compilerArgs = @('-nologo', '-target:library', '-nostdlib+', '-langversion:9',
        ('-out:' + (Join-Path $output "Almutlaq.Showroom.$target.dll")), ('-define:' + $defines))
    $compilerArgs += @($references | ForEach-Object { '-r:' + $_.FullName })
    $compilerArgs += @(Get-ChildItem (Join-Path $root 'unity\Assets\Almutlaq\*.cs') | ForEach-Object FullName)
    & $dotnet $Compiler @compilerArgs
    if ($LASTEXITCODE) { throw "$target runtime-source compilation failed." }
    Write-Host "$target runtime-source compilation passed."
}
Write-Host 'Source check only: excludes asmdef reference resolution, PICO SDK, Assets/Editor scripts, Unity edit-mode tests, IL2CPP, APK packaging and physical acceptance.'
