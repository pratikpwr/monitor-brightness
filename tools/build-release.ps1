<#
  build-release.ps1 - build dist\MonitorBrightness.zip for a GitHub release.
  Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools\build-release.ps1
  The version comes from $Version in install.ps1.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = [regex]::Match((Get-Content (Join-Path $root 'install.ps1') -Raw), "\`$Version\s*=\s*'([^']+)'").Groups[1].Value
if (-not $version) { throw 'Could not read $Version from install.ps1' }

$dist  = Join-Path $root 'dist'
$stage = Join-Path $dist 'MonitorBrightness'
Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null

$files = 'Install.cmd', 'install.ps1', 'app.cs', 'ui.cs', 'ddc.cs', 'app.manifest', 'brightness.ps1', 'README.md', 'LICENSE'
foreach ($f in $files) { Copy-Item (Join-Path $root $f) $stage }
Copy-Item (Join-Path $root 'assets\icon.ico') $stage

# Plain-text uninstaller for people who prefer double-clicking.
Set-Content -Path (Join-Path $stage 'Uninstall.cmd') -Encoding ASCII -Value @'
@echo off
rem Removes Monitor Brightness (you can also use Settings > Apps > Installed apps).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\MonitorBrightness\install.ps1" -Uninstall
"%SystemRoot%\System32\timeout.exe" /t 5 >nul
'@

$zip = Join-Path $dist 'MonitorBrightness.zip'
# Write entries by hand with "/" separators: Compress-Archive and ZipFile in Windows PowerShell 5.1
# store "\" separators, which other unzip tools treat as part of the file name.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem $stage -File | Sort-Object Name) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName,
            "MonitorBrightness/$($file.Name)", [IO.Compression.CompressionLevel]::Optimal)
    }
}
finally { $archive.Dispose() }
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
"version  $version"
"zip      $zip ($([int]((Get-Item $zip).Length / 1KB)) KB)"
"sha256   $hash"
