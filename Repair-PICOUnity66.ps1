param([string]$ProjectPath = (Join-Path $PSScriptRoot 'unity'))
$ErrorActionPreference = 'Stop'
$cache = Join-Path $ProjectPath 'Library\PackageCache'
$package = @(Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'com.unity.xr.picoxr@c93a59bab88d*' })
if ($package.Count -ne 1) { throw 'Resolve the pinned PICO package in Unity Safe Mode first, then run this repair again.' }
$metadata = Get-Content (Join-Path $package[0].FullName 'package.json') -Raw | ConvertFrom-Json
if ($metadata.name -ne 'com.unity.xr.picoxr' -or $metadata.version -ne '3.4.0') { throw 'Unexpected PICO package. Review compatibility before patching.' }
$path = Join-Path $package[0].FullName 'SpatialAudio\Runtime\PXR_Audio_Spatializer_SceneGeometry.cs'
$source = [IO.File]::ReadAllText($path)
if ($source.Contains('EntityId.ToULong(GetEntityId())')) { Write-Host 'PICO EntityId compatibility fix already applied.'; return }
$old = 'GetInstanceID() + "_" +'
if (($source.Split(@($old), [StringSplitOptions]::None).Length - 1) -ne 1) { throw 'PICO source differs from the expected single filename-identifier call. No change made.' }
$new = @'
#if UNITY_6000_4_OR_NEWER
                                              EntityId.ToULong(GetEntityId()) + "_" +
#else
                                              GetInstanceID() + "_" +
#endif
'@
# The preprocessor directive must start on its own line, not after the expression.
$updated = $source.Replace($old, ([Environment]::NewLine + $new.TrimEnd() + [Environment]::NewLine))
$backup = Join-Path $PSScriptRoot 'builds\pico-compat-backup'
New-Item -ItemType Directory -Force $backup | Out-Null
$backupFile = Join-Path $backup 'PXR_Audio_Spatializer_SceneGeometry.before-entityid.cs.txt'
if (-not (Test-Path -LiteralPath $backupFile)) { [IO.File]::WriteAllText($backupFile, $source, [Text.UTF8Encoding]::new($false)) }
$file = Get-Item -LiteralPath $path
$wasReadOnly = $file.IsReadOnly
try {
    if ($wasReadOnly) { $file.IsReadOnly = $false }
    [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($false))
} finally { if ($wasReadOnly) { (Get-Item -LiteralPath $path).IsReadOnly = $true } }
Write-Host 'Applied the PICO upstream EntityId conditional to the pinned spatial-audio filename code.'
Write-Host 'This local PackageCache edit must be repeated after a package-cache refresh. Reopen/reimport in Unity and check the Console.'
