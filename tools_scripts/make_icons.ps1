# Builds all game icons from art/icon_source.jpg:
#   icon.png (512)            project / window icon
#   icon.ico (16..256)        Windows .exe icon (PNG-compressed ICO)
#   icon_192.png              Android launcher icon
#   icon_fg_432.png / icon_bg_432.png   Android adaptive icon layers
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Join-Path $Root 'art\icon_source.jpg'))

function Save-Scaled([int]$size, [string]$path, [double]$inset = 0.0, $bg = $null) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($bg) { $g.Clear($bg) } else { $g.Clear([System.Drawing.Color]::Transparent) }
    $pad = [int]($size * $inset)
    if ($src) { $g.DrawImage($src, $pad, $pad, $size - 2 * $pad, $size - 2 * $pad) }
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

Save-Scaled 512 (Join-Path $Root 'icon.png')
Save-Scaled 192 (Join-Path $Root 'icon_192.png')
Save-Scaled 432 (Join-Path $Root 'icon_fg_432.png') 0.17
# background layer: the icon's dark navy
$bg = New-Object System.Drawing.Bitmap 432, 432
$gb = [System.Drawing.Graphics]::FromImage($bg)
$gb.Clear([System.Drawing.Color]::FromArgb(255, 8, 26, 34))
$gb.Dispose()
$bg.Save((Join-Path $Root 'icon_bg_432.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bg.Dispose()

# ICO with PNG-compressed images
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()
foreach ($s in $sizes) {
    $tmp = [System.IO.Path]::GetTempFileName()
    Save-Scaled $s $tmp
    $pngs += , [System.IO.File]::ReadAllBytes($tmp)
    Remove-Item $tmp
}
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $b = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$pngs[$i].Length); $bw.Write([UInt32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
[System.IO.File]::WriteAllBytes((Join-Path $Root 'icon.ico'), $ms.ToArray())
$bw.Dispose()
$src.Dispose()
Write-Host "Icons written to $Root"
