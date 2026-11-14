<#
  install.ps1 - install Monitor Brightness for the current user (no admin needed).

  App files : %LOCALAPPDATA%\MonitorBrightness
  Tray app  : starts automatically when you sign in (Startup folder shortcut)
  Shortcuts : Desktop and Start menu "Monitor Brightness" (start the tray app / open the slider)
  Run with -Uninstall to remove everything.
#>
param([switch]$Uninstall)

$app      = Join-Path $env:LOCALAPPDATA 'MonitorBrightness'
$programs = [Environment]::GetFolderPath('Programs')
$startup  = [Environment]::GetFolderPath('Startup')
$desktop  = [Environment]::GetFolderPath('Desktop')
$links    = @(
    (Join-Path $programs 'Monitor Brightness.lnk'),
    (Join-Path $desktop  'Monitor Brightness.lnk'),
    (Join-Path $startup  'Monitor Brightness.lnk')
)

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
    Remove-Item ($links + $app) -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $app) { Write-Host "Shortcuts removed, but could not delete $app (a file is in use). Delete it by hand." }
    else { Write-Host "Uninstalled." }
    return
}

New-Item -ItemType Directory -Force $app | Out-Null
if ((Resolve-Path $PSScriptRoot).Path -ne (Resolve-Path $app).Path) {
    foreach ($f in 'ddc.cs', 'ui.cs', 'tray.ps1', 'brightness.ps1', 'install.ps1') {
        Copy-Item (Join-Path $PSScriptRoot $f) $app -Force
    }
}

# conhost --headless runs PowerShell without a console window flashing up.
$conhost = Join-Path $env:WINDIR 'System32\conhost.exe'
$ps      = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$args_   = "--headless `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$app\tray.ps1`""

$shell = New-Object -ComObject WScript.Shell
foreach ($path in $links) {
    $s = $shell.CreateShortcut($path)
    $s.TargetPath = $conhost
    $s.Arguments = $args_
    $s.WorkingDirectory = $app
    $s.Description = 'Monitor brightness slider (tray app)'
    $s.IconLocation = "$env:WINDIR\System32\imageres.dll,101"
    $s.Save()
}

Start-Process -FilePath $conhost -ArgumentList $args_ -WorkingDirectory $app
Write-Host "Installed to $app and started the tray app."
