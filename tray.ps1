<#
  tray.ps1 - Monitor Brightness tray app (external monitors over DDC/CI).

  Tray icon : left-click opens the brightness flyout, right-click for presets and Exit.
  Hotkeys   : Ctrl+Alt+B         open / close the flyout
              Ctrl+Alt+PageUp    10% brighter
              Ctrl+Alt+PageDown  10% dimmer
  Running it again while it is already running just opens the flyout.
#>
$ErrorActionPreference = 'Stop'
$Step = 10
$LogFile = Join-Path $PSScriptRoot 'tray.log'
$DebugLog = Test-Path (Join-Path $PSScriptRoot 'debug.flag')
function Write-Log($msg) {
    try { Add-Content -Path $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss.fff}  {1}" -f (Get-Date), $msg) } catch {}
}
function Write-Trace($msg) { if ($DebugLog) { Write-Log $msg } }

# ---- single instance: a second launch asks the running one to show the flyout ----
$showEvent = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\MonitorBrightnessShow')
$exitEvent = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\MonitorBrightnessExit')  # set by install.ps1
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MonitorBrightnessTray', [ref]$createdNew)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'ui.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
if (-not $createdNew) { [Native]::AllowAnyForeground(); [void]$showEvent.Set(); exit 0 }

try {
[Native]::EnableDpiAwareness()
Add-Type -Path (Join-Path $PSScriptRoot 'ddc.cs')
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- monitors: re-read on each use so sleep / reconnect does not leave stale handles ----
$script:all = $null
$script:handles = @()
function Update-Monitors {
    if ($script:all) { try { [Ddc]::Release($script:all) } catch {} }
    $script:all = [Ddc]::All()
    $script:handles = @($script:all | ForEach-Object { $_.hPhysicalMonitor } | Where-Object { [Ddc]::Get($_) -ge 0 })
}
function Get-Level { if ($script:handles.Count) { [Ddc]::Get($script:handles[0]) } else { -1 } }
$script:lastSet = -1; $script:lastSetAt = 0
function Set-Level([int]$v) {
    $v = [Math]::Max(0, [Math]::Min(100, $v))
    $ok = $false
    foreach ($h in $script:handles) { if ([Ddc]::Set($h, $v)) { $ok = $true } }
    if ($ok) { $script:lastSet = $v; $script:lastSetAt = [Environment]::TickCount; Set-Tip $v }
    $v
}

# Friendly name of the external monitor (built-in laptop panels are the ones with WMI brightness).
function Get-MonitorName {
    try {
        $internal = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue | ForEach-Object InstanceName)
        $ext = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction Stop |
            Where-Object { $internal -notcontains $_.InstanceName } | Select-Object -First 1
        if ($ext) {
            $maker = -join ($ext.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            $model = -join ($ext.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            $brand = @{ ACR = 'Acer'; DEL = 'Dell'; SAM = 'Samsung'; GSM = 'LG'; AUS = 'ASUS'; LEN = 'Lenovo'; HWP = 'HP'; BNQ = 'BenQ'; AOC = 'AOC'; PHL = 'Philips'; MSI = 'MSI'; VSC = 'ViewSonic' }[$maker]
            if (-not $brand) { $brand = $maker }
            $n = "$brand $model".Trim()
            if ($n) { return $n }
        }
    } catch {}
    'External monitor'
}

# ---- tray icon (sun), white on a dark taskbar, black on a light one ----
function New-SunIcon {
    $light = $false
    try { $light = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' SystemUsesLightTheme) -eq 1 } catch {}
    $color = if ($light) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $brush = New-Object System.Drawing.SolidBrush $color
    $pen = New-Object System.Drawing.Pen $color, 3
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.FillEllipse($brush, 9, 9, 14, 14)
    for ($i = 0; $i -lt 8; $i++) {
        $a = $i * [Math]::PI / 4
        $g.DrawLine($pen, 16 + 10 * [Math]::Cos($a), 16 + 10 * [Math]::Sin($a), 16 + 14 * [Math]::Cos($a), 16 + 14 * [Math]::Sin($a))
    }
    $g.Dispose(); $brush.Dispose(); $pen.Dispose()
    [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = New-SunIcon
$tray.Text = 'Monitor brightness'
function Set-Tip($v) { $tray.Text = if ($v -ge 0) { "Monitor brightness: $v%" } else { 'Monitor brightness (DDC/CI not available)' } }

# ---- the flyout ----
$flyout = New-Object BrightnessFlyout
$flyout.MonitorName = Get-MonitorName

# DDC/CI writes are slow: apply the latest value on a short timer, not on every slider tick.
$script:pending = -1
$applyTimer = New-Object System.Windows.Forms.Timer
$applyTimer.Interval = 120
$applyTimer.add_Tick({
    try {
        if ($script:pending -ge 0) { $v = $script:pending; $script:pending = -1; [void](Set-Level $v) }
        else { $applyTimer.Stop() }
    } catch { Write-Log "apply: $_" }
})
$flyout.add_ValueChanged({ $script:pending = $flyout.Value; $applyTimer.Start() })

# 'slider' = opened to use; 'osd' = shown briefly by the PageUp/PageDown hotkeys.
$script:mode = ''
$script:hiddenAt = 0
function Hide-Flyout {
    $hideTimer.Stop()
    if ($flyout.Visible) { $script:hiddenAt = [Environment]::TickCount; $flyout.Hide() }
    $script:mode = ''
}
$hideTimer = New-Object System.Windows.Forms.Timer
$hideTimer.Interval = 1500
$hideTimer.add_Tick({ $hideTimer.Stop(); if (-not [Native]::IsForeground($flyout.Handle)) { Hide-Flyout } })

$flyout.add_Activated({ if ([Native]::IsForeground($flyout.Handle)) { $hideTimer.Stop(); $script:mode = 'slider' } })
$flyout.add_Deactivate({ Write-Trace 'deactivate'; Hide-Flyout })
$flyout.add_EscapePressed({ Hide-Flyout })
$flyout.add_FormClosing({ param($s, $e) if ($e.CloseReason -eq 'UserClosing') { $e.Cancel = $true; Hide-Flyout } })

function Show-Slider {
    try {
        $hideTimer.Stop()
        Update-Monitors
        $v = Get-Level
        if ($v -lt 0) {
            $tray.ShowBalloonTip(4000, 'Monitor brightness', "No monitor answered DDC/CI. Turn DDC/CI on in the monitor's own menu.", 'Warning')
            return
        }
        $flyout.SetValue($v); Set-Tip $v
        $script:mode = 'slider'
        $flyout.ShowAt($true)
        $fg = [Native]::IsForeground($flyout.Handle)
        Write-Trace "show slider, foreground=$fg"
        # If Windows refused to give it focus, it can't close on "click elsewhere", so close it after a while.
        if (-not $fg) { $hideTimer.Interval = 8000; $hideTimer.Start() }
    } catch { Write-Log "show: $_" }
}
function Switch-Slider {
    Write-Trace "toggle: visible=$($flyout.Visible) mode=$script:mode"
    if ($flyout.Visible -and $script:mode -eq 'slider') { Hide-Flyout } else { Show-Slider }
}

function Step-Brightness([int]$delta) {
    try {
        if ($script:pending -ge 0) { [void](Set-Level $script:pending); $script:pending = -1 }
        if (-not $flyout.Visible) { Update-Monitors }
        # Step from the value we just set: reading it back right after a write can return the old value.
        $cur = if ($script:lastSet -ge 0 -and ([Environment]::TickCount - $script:lastSetAt) -lt 5000) { $script:lastSet } else { Get-Level }
        if ($cur -lt 0) { Update-Monitors; $cur = Get-Level }
        if ($cur -lt 0) { return }
        $v = Set-Level ($cur + $delta)
        $flyout.SetValue($v)
        if (-not $flyout.Visible) { $script:mode = 'osd'; $flyout.ShowAt($false) }
        if ($script:mode -eq 'osd') { $hideTimer.Stop(); $hideTimer.Interval = 1500; $hideTimer.Start() }
    } catch { Write-Log "step: $_" }
}

$flyout.Prime()

# ---- tray menu ----
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Open brightness  (Ctrl+Alt+B)', $null, { Show-Slider })
[void]$menu.Items.Add('-')
foreach ($p in [BrightnessFlyout]::Presets) {
    $item = $menu.Items.Add("$p%", $null, { param($s) try { Update-Monitors; $v = Set-Level ([int]$s.Tag); $flyout.SetValue($v) } catch { Write-Log "menu: $_" } })
    $item.Tag = $p
}
[void]$menu.Items.Add('-')
[void]$menu.Items.Add('Exit', $null, { [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu
# Pressing on the tray icon already hid the flyout (it lost focus); don't reopen it on mouse-up.
$tray.add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left' -and ([Environment]::TickCount - $script:hiddenAt) -gt 400) { Switch-Slider } })

# ---- global hotkeys (NOREPEAT: holding a key would queue slow DDC/CI writes and overshoot) ----
$MOD_ALT = 0x1; $MOD_CTRL = 0x2; $NOREPEAT = 0x4000
$hk = New-Object HotkeyWindow
$failed = @()
if (-not $hk.Register(1, $MOD_CTRL -bor $MOD_ALT -bor $NOREPEAT, 0x42)) { $failed += 'Ctrl+Alt+B' }
if (-not $hk.Register(2, $MOD_CTRL -bor $MOD_ALT -bor $NOREPEAT, 0x21)) { $failed += 'Ctrl+Alt+PageUp' }
if (-not $hk.Register(3, $MOD_CTRL -bor $MOD_ALT -bor $NOREPEAT, 0x22)) { $failed += 'Ctrl+Alt+PageDown' }
$hk.add_Pressed({
    param($s, $e)
    Write-Trace "hotkey $($e.Id)"
    switch ($e.Id) { 1 { Switch-Slider } 2 { Step-Brightness $Step } 3 { Step-Brightness (-$Step) } }
})

# ---- second launch -> show flyout; install.ps1 -> exit ----
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 300
$pollTimer.add_Tick({
    if ($exitEvent.WaitOne(0)) { [System.Windows.Forms.Application]::Exit(); return }
    if ($showEvent.WaitOne(0)) { Show-Slider }
})
$pollTimer.Start()
# Log unexpected errors instead of showing the WinForms error dialog.
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) Write-Log "unhandled: $($e.Exception.Message)" })

Update-Monitors
Set-Tip (Get-Level)
$tray.Visible = $true
if ($failed.Count) {
    $msg = "Another app is already using: $($failed -join ', ')"
    Write-Log $msg
    $tray.ShowBalloonTip(5000, 'Monitor brightness', $msg, 'Warning')
}
Write-Log "started"

[System.Windows.Forms.Application]::Run()
}
catch { Write-Log "fatal: $_" }
finally {
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
    if ($hk) { $hk.Dispose() }
    if ($script:all) { try { [Ddc]::Release($script:all) } catch {} }
    $mutex.ReleaseMutex()
    Write-Log "stopped"
}
