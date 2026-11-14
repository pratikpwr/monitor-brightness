<#
  make-assets.ps1 - regenerate assets\icon.ico (app icon) and docs\social-preview.png (GitHub social card).
  Run from the repo root:  powershell -ExecutionPolicy Bypass -File tools\make-assets.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force (Join-Path $root 'assets'), (Join-Path $root 'docs') | Out-Null

# Rounded dark tile with an amber sun, drawn at any size.
function New-IconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $s = $size / 256.0
    $tile = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 56 * $s; $m = 8 * $s; $w = $size - 2 * $m
    $tile.AddArc($m, $m, $r, $r, 180, 90); $tile.AddArc($m + $w - $r, $m, $r, $r, 270, 90)
    $tile.AddArc($m + $w - $r, $m + $w - $r, $r, $r, 0, 90); $tile.AddArc($m, $m + $w - $r, $r, $r, 90, 90)
    $tile.CloseFigure()
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.PointF]::new(0, 0)), ([System.Drawing.PointF]::new(0, $size)),
        ([System.Drawing.Color]::FromArgb(58, 58, 64)), ([System.Drawing.Color]::FromArgb(28, 28, 32))
    $g.FillPath($bg, $tile)
    $sun = [System.Drawing.Color]::FromArgb(255, 196, 40)
    $brush = New-Object System.Drawing.SolidBrush $sun
    $pen = New-Object System.Drawing.Pen $sun, ([Math]::Max(1.5, 18 * $s))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $c = $size / 2.0; $cr = 44 * $s
    $g.FillEllipse($brush, $c - $cr, $c - $cr, 2 * $cr, 2 * $cr)
    for ($i = 0; $i -lt 8; $i++) {
        $a = $i * [Math]::PI / 4
        $g.DrawLine($pen, $c + 66 * $s * [Math]::Cos($a), $c + 66 * $s * [Math]::Sin($a), $c + 92 * $s * [Math]::Cos($a), $c + 92 * $s * [Math]::Sin($a))
    }
    $g.Dispose(); $bg.Dispose(); $brush.Dispose(); $pen.Dispose(); $tile.Dispose()
    $bmp
}

# ICO with PNG-compressed images (supported since Windows Vista).
$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$pngs = foreach ($sz in $sizes) {
    $b = New-IconBitmap $sz; $ms = New-Object System.IO.MemoryStream
    $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); , $ms.ToArray()
}
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $out
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
[System.IO.File]::WriteAllBytes((Join-Path $root 'assets\icon.ico'), $out.ToArray())
"assets\icon.ico written ($($sizes -join ', ') px)"
$png = New-IconBitmap 256
$png.Save((Join-Path $root 'assets\icon.png'), [System.Drawing.Imaging.ImageFormat]::Png); $png.Dispose()
"assets\icon.png written (256 px, for the README)"

# Social preview card, 1280x640.
$W = 1280; $H = 640
$card = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($card)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Point]::new(0, 0)), ([System.Drawing.Point]::new($W, $H)),
    ([System.Drawing.Color]::FromArgb(32, 30, 40)), ([System.Drawing.Color]::FromArgb(14, 14, 18))
$g.FillRectangle($bg, 0, 0, $W, $H)
$icon = New-IconBitmap 112
$g.DrawImage($icon, 80, 96, 112, 112)
$white = [System.Drawing.Brushes]::White
$grey = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 200, 205))
$g.DrawString('Monitor Brightness', (New-Object System.Drawing.Font('Segoe UI Semibold', 50, [System.Drawing.GraphicsUnit]::Pixel)), $white, 80, 236)
$g.DrawString("Control your external monitor's brightness`nfrom Windows 11 and 10 - no monitor buttons.",
    (New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.GraphicsUnit]::Pixel)), $grey, 82, 312)
$g.DrawString('Tray app  |  Hotkeys  |  DDC/CI  |  Free & open source',
    (New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.GraphicsUnit]::Pixel)), $grey, 82, 440)
$shot = [System.Drawing.Image]::FromFile((Join-Path $root 'docs\flyout.png'))
$sw = 560; $sh = [int]($shot.Height * $sw / $shot.Width)
$g.DrawImage($shot, $W - $sw - 70, [int](($H - $sh) / 2), $sw, $sh)
$shot.Dispose(); $icon.Dispose(); $g.Dispose()
$card.Save((Join-Path $root 'docs\social-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$card.Dispose()
"docs\social-preview.png written (${W}x${H})"
