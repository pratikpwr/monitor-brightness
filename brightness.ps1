<#
  brightness.ps1 - set external monitor brightness over DDC/CI from the command line.

    .\brightness.ps1          show current brightness
    .\brightness.ps1 40       set to 40%
    .\brightness.ps1 +10      10% brighter
    .\brightness.ps1 -10      10% dimmer
#>
$Value = "$($args[0])"
Add-Type -Path (Join-Path $PSScriptRoot 'ddc.cs')

$monitors = [Ddc]::All()
$found = $false
foreach ($m in $monitors) {
    $h = $m.hPhysicalMonitor
    $cur = [Ddc]::Get($h)
    if ($cur -lt 0) { continue }   # built-in laptop screen, or DDC/CI off: skip
    $found = $true
    if ($Value -eq '') { Write-Host "External monitor: $cur%"; continue }
    $target = if ($Value -match '^[+-]') { $cur + [int]$Value } else { [int]$Value }
    $target = [Math]::Max(0, [Math]::Min(100, $target))
    if ([Ddc]::Set($h, $target)) { Write-Host "External monitor: $cur% -> $target%" }
    else { Write-Host "External monitor: failed to set brightness" }
}
if ($monitors.Count) { [Ddc]::Release($monitors) }
if (-not $found) { Write-Host "No monitor answered DDC/CI. Turn DDC/CI on in the monitor's own menu."; exit 1 }
