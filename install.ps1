<#
  install.ps1 - install, update or uninstall Monitor Brightness for the current user (no admin needed).

  App files : %LOCALAPPDATA%\MonitorBrightness
  Tray app  : starts automatically when you sign in (Startup folder shortcut)
  Shortcuts : Desktop and Start menu "Monitor Brightness" (start the tray app / open the slider)
  Settings  : listed in Settings > Apps > Installed apps, with an Uninstall button
  Run with -Uninstall to remove everything.
#>
param([switch]$Uninstall)

$Version  = '1.0.0'
$RepoUrl  = 'https://github.com/pratikpwr/monitor-brightness'
$Files    = 'ddc.cs', 'ui.cs', 'tray.ps1', 'brightness.ps1', 'install.ps1', 'icon.ico'

$app      = Join-Path $env:LOCALAPPDATA 'MonitorBrightness'
$programs = [Environment]::GetFolderPath('Programs')
$startup  = [Environment]::GetFolderPath('Startup')
$desktop  = [Environment]::GetFolderPath('Desktop')
$links    = @(
    (Join-Path $programs 'Monitor Brightness.lnk'),
    (Join-Path $desktop  'Monitor Brightness.lnk'),
    (Join-Path $startup  'Monitor Brightness.lnk')
)
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MonitorBrightness'

function Test-TrayRunning {
    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting('Local\MonitorBrightnessTray', [ref]$m)) { $m.Dispose(); return $true }
    $false
}

function Stop-Tray {
    # 1. Ask the running tray app to exit cleanly (removes its icon properly).
    $ev = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\MonitorBrightnessExit')
    if (Test-TrayRunning) {
        [void]$ev.Set()
        for ($i = 0; $i -lt 25 -and (Test-TrayRunning); $i++) { Start-Sleep -Milliseconds 200 }
    }
    [void]$ev.Reset(); $ev.Dispose()   # never leave it signalled for the copy we start next

    # 2. Fallback: force-stop this app's copies that are left (installed folder or a monitor-brightness clone,
    #    Windows PowerShell or PowerShell 7). Other scripts that happen to be called tray.ps1 are not touched.
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '(?i)monitor-?brightness[^"]*\\(tray|slider)\.ps1' })
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($procs) { Wait-Process -Id $procs.ProcessId -Timeout 5 -ErrorAction SilentlyContinue }
}

# Leftovers from the first version (shortcut hotkeys that would clash with the tray app's own).
$old = @((Join-Path $programs 'Monitor Brightness'), (Join-Path $app 'slider.ps1'))

Stop-Tray
Remove-Item $old -Recurse -Force -ErrorAction SilentlyContinue

if ($Uninstall) {
    Remove-Item $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item ($links + $app) -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $app) { Write-Host "Shortcuts removed, but could not delete $app (a file is in use). Delete it by hand." }
    else { Write-Host "Monitor Brightness has been uninstalled." }
    return
}

# ---- copy the app ----
# Files can sit next to this script (release ZIP) or in assets\ (the icon in a git clone).
New-Item -ItemType Directory -Force $app | Out-Null
$fromSelf = (Resolve-Path $PSScriptRoot).Path -eq (Resolve-Path $app).Path
if (-not $fromSelf) {
    foreach ($f in $Files) {
        $src = Join-Path $PSScriptRoot $f
        if (-not (Test-Path $src)) { $src = Join-Path $PSScriptRoot "assets\$f" }
        if (-not (Test-Path $src)) { Write-Host "Missing file: $f. Download the full release ZIP and try again."; exit 1 }
        Copy-Item $src $app -Force
    }
}
# Files from a downloaded ZIP are marked as "from the internet"; the app is trusted once installed.
Get-ChildItem $app -File | Unblock-File -ErrorAction SilentlyContinue

# ---- shortcuts (conhost --headless runs PowerShell without a console window flashing up) ----
$conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
$ps      = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args_   = "--headless `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$app\tray.ps1`""
$icon    = Join-Path $app 'icon.ico'

$shell = New-Object -ComObject WScript.Shell
foreach ($path in $links) {
    $s = $shell.CreateShortcut($path)
    $s.TargetPath = $conhost
    $s.Arguments = $args_
    $s.WorkingDirectory = $env:USERPROFILE
    $s.Description = 'Control your external monitor brightness'
    $s.IconLocation = "$icon,0"
    $s.Save()
}

# ---- Settings > Apps entry (per user, with Uninstall button) ----
$kb = [int]((Get-ChildItem $app -File | Measure-Object Length -Sum).Sum / 1KB)
New-Item -Path $uninstallKey -Force | Out-Null
$uninstallCmd = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app\install.ps1`" -Uninstall"
$values = @{
    DisplayName          = 'Monitor Brightness'
    DisplayVersion       = $Version
    Publisher            = 'pratikpwr'
    DisplayIcon          = $icon
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

Start-Process -FilePath $conhost -ArgumentList $args_ -WorkingDirectory $env:USERPROFILE
Write-Host "Monitor Brightness $Version is installed and running."
Write-Host "Look for the sun icon in the system tray, or press Ctrl+Alt+B."
