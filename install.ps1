<#
  install.ps1 - install, update or uninstall Monitor Brightness for the current user (no admin needed).

  Builds MonitorBrightness.exe from the C# sources with the C# compiler that ships with Windows
  (.NET Framework), then installs it:
    App       : %LOCALAPPDATA%\MonitorBrightness\MonitorBrightness.exe  (sources kept in .\src for rebuilding)
    Auto-start: HKCU ...\CurrentVersion\Run  (toggle it from the tray menu, "Start with Windows")
    Shortcuts : Start menu and Desktop "Monitor Brightness"
    Settings  : Settings > Apps > Installed apps, with an Uninstall button
  Run with -Uninstall to remove everything.
#>
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$Version  = '1.1.0'
$RepoUrl  = 'https://github.com/pratikpwr/monitor-brightness'
$Sources  = 'app.cs', 'ui.cs', 'ddc.cs', 'app.manifest', 'icon.ico'

$app      = Join-Path $env:LOCALAPPDATA 'MonitorBrightness'
$exe      = Join-Path $app 'MonitorBrightness.exe'
$programs = [Environment]::GetFolderPath('Programs')
$startup  = [Environment]::GetFolderPath('Startup')
$desktop  = [Environment]::GetFolderPath('Desktop')
$links    = @((Join-Path $programs 'Monitor Brightness.lnk'), (Join-Path $desktop 'Monitor Brightness.lnk'))
$runKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MonitorBrightness'

function Test-TrayRunning {
    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting('Local\MonitorBrightnessTray', [ref]$m)) { $m.Dispose(); return $true }
    $false
}

function Stop-Tray {
    # 1. Ask the running app to exit cleanly (removes its tray icon properly).
    $ev = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\MonitorBrightnessExit')
    if (Test-TrayRunning) {
        [void]$ev.Set()
        for ($i = 0; $i -lt 25 -and (Test-TrayRunning); $i++) { Start-Sleep -Milliseconds 200 }
    }
    [void]$ev.Reset(); $ev.Dispose()   # never leave it signalled for the copy we start next

    # 2. Fallback: force-stop copies that are left: the installed exe, and the old PowerShell version
    #    (tray.ps1 / slider.ps1 from the installed folder or a monitor-brightness clone).
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='MonitorBrightness.exe' OR Name='powershell.exe' OR Name='pwsh.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and (
            ($_.Name -eq 'MonitorBrightness.exe' -and $_.ExecutablePath -and
                $_.ExecutablePath.StartsWith("$app\", [StringComparison]::OrdinalIgnoreCase)) -or
            $_.CommandLine -match '(?i)monitor-?brightness[^"]*\\(tray|slider)\.ps1') })
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($procs) { Wait-Process -Id $procs.ProcessId -Timeout 5 -ErrorAction SilentlyContinue }
}

# Find a source file next to this script, in assets\ (git clone) or in src\ (installed copy).
function Find-Source($name) {
    foreach ($dir in $PSScriptRoot, (Join-Path $PSScriptRoot 'assets'), (Join-Path $PSScriptRoot 'src')) {
        $p = Join-Path $dir $name
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    $null
}

function Copy-IfDifferent($from, $to) {
    if ((Test-Path $to) -and ((Resolve-Path $from).Path -eq (Resolve-Path $to).Path)) { return }
    Copy-Item $from $to -Force
}

# ======================================================================== uninstall
if ($Uninstall) {
    Stop-Tray
    Remove-ItemProperty -Path $runKey -Name 'MonitorBrightness' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name 'MonitorBrightness' -ErrorAction SilentlyContinue
    Remove-Item $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ($links + (Join-Path $startup 'Monitor Brightness.lnk') + (Join-Path $programs 'Monitor Brightness')) -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $app -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $app) { Write-Host "Removed, but could not delete $app (a file is in use). Delete it by hand." }
    else { Write-Host 'Monitor Brightness has been uninstalled.' }
    return
}

# ======================================================================== build
$src = @{}
foreach ($f in $Sources) {
    $src[$f] = Find-Source $f
    if (-not $src[$f]) { Write-Host "Missing file: $f. Download the full release ZIP and try again." -ForegroundColor Red; exit 1 }
}
# The .NET Framework compiler that ships with Windows (also found when this runs under PowerShell 7).
$csc = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { Write-Host '.NET Framework 4 C# compiler (csc.exe) not found in Windows\Microsoft.NET.' -ForegroundColor Red; exit 1 }

$build = Join-Path $env:TEMP ('MonitorBrightness-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $build | Out-Null
try {
    Write-Host 'Building Monitor Brightness...'
    $ErrorActionPreference = 'Continue'   # csc output must not be turned into terminating errors
    $out = & $csc /nologo /target:winexe /optimize+ "/out:$build\MonitorBrightness.exe" "/win32icon:$($src['icon.ico'])" `
        "/win32manifest:$($src['app.manifest'])" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Management.dll `
        $src['app.cs'] $src['ui.cs'] $src['ddc.cs'] 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$build\MonitorBrightness.exe")) {
        $out | Where-Object { $_ -match 'error' } | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host 'Build failed.' -ForegroundColor Red
        exit 1
    }

    # ==================================================================== install
    Stop-Tray
    New-Item -ItemType Directory -Force $app, "$app\src" | Out-Null
    Copy-Item "$build\MonitorBrightness.exe" $exe -Force
    foreach ($f in $Sources) { Copy-IfDifferent $src[$f] (Join-Path "$app\src" $f) }
    Copy-IfDifferent $src['icon.ico'] (Join-Path $app 'icon.ico')
    Copy-IfDifferent $src['ddc.cs'] (Join-Path $app 'ddc.cs')          # used by brightness.ps1
    foreach ($f in 'install.ps1', 'brightness.ps1') {
        $p = Find-Source $f
        if ($p) { Copy-IfDifferent $p (Join-Path $app $f) }
    }
}
finally { Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue }

# Remove what older versions installed: the PowerShell tray app, its startup-folder shortcut, old menu folder.
Remove-Item "$app\tray.ps1", "$app\ui.cs", "$app\slider.ps1", (Join-Path $startup 'Monitor Brightness.lnk'),
    (Join-Path $programs 'Monitor Brightness') -Recurse -Force -ErrorAction SilentlyContinue
# Files that came from a downloaded ZIP carry the "from the internet" mark; clear it on the installed copy.
Get-ChildItem $app -File -Recurse | Unblock-File -ErrorAction SilentlyContinue

# ---- shortcuts point straight at the exe ----
$shell = New-Object -ComObject WScript.Shell
foreach ($path in $links) {
    $s = $shell.CreateShortcut($path)
    $s.TargetPath = $exe
    $s.Arguments = ''
    $s.WorkingDirectory = $app
    $s.Description = 'Control your external monitor brightness'
    $s.IconLocation = "$exe,0"
    $s.Save()
}

# ---- start with Windows ----
# Never use New-Item -Force on the Run key: on an existing key it recreates it and wipes other apps' entries.
if (-not (Test-Path $runKey)) { New-Item -Path $runKey | Out-Null }
Set-ItemProperty -Path $runKey -Name 'MonitorBrightness' -Value "`"$exe`""
# If the user switched it off in Settings > Apps > Startup (or Task Manager), that choice is kept.

# ---- Settings > Apps entry (per user, with Uninstall button) ----
$ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$kb = [int]((Get-ChildItem $app -File -Recurse | Measure-Object Length -Sum).Sum / 1KB)
New-Item -Path $uninstallKey -Force | Out-Null
$uninstallCmd = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app\install.ps1`" -Uninstall"
$values = @{
    DisplayName          = 'Monitor Brightness'
    DisplayVersion       = $Version
    Publisher            = 'pratikpwr'
    DisplayIcon          = "$exe,0"
    InstallLocation      = $app
    UninstallString      = $uninstallCmd
    QuietUninstallString = $uninstallCmd
    URLInfoAbout         = $RepoUrl
    HelpLink             = "$RepoUrl#troubleshooting"
    InstallDate          = (Get-Date -Format 'yyyyMMdd')
}
foreach ($k in $values.Keys) { Set-ItemProperty -Path $uninstallKey -Name $k -Value $values[$k] }
foreach ($k in 'NoModify', 'NoRepair', 'EstimatedSize') {
    $v = if ($k -eq 'EstimatedSize') { $kb } else { 1 }
    New-ItemProperty -Path $uninstallKey -Name $k -Value $v -PropertyType DWord -Force | Out-Null
}

Start-Process -FilePath $exe -WorkingDirectory $app
Write-Host "Monitor Brightness $Version is installed and running."
Write-Host 'Look for the sun icon in the system tray, or press Ctrl+Alt+B.'
