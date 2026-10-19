# Builds all game icons from art/ (drawn by tools_scripts/icon/final.py):
#   icon.png (512)            project / window icon                  <- art/icon_source.png
#   icon.ico (16..256)        Windows .exe icon (PNG-compressed ICO)  <- art/icon_source.png
#   icon_192.png              Android launcher icon, the site's icon  <- art/icon_source.png
#   icon_fg_432.png / icon_bg_432.png   Android adaptive icon layers  <- art/icon_fg.png, art/icon_bg.png
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Join-Path $Root 'art\icon_source.png'))

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
# Android adaptive layers: the sky and the city fill the background; the letters and the intercept
# sit inside the round mask's safe zone (inset 19%)
$full = $src
$src = [System.Drawing.Image]::FromFile((Join-Path $Root 'art\icon_fg.png'))
Save-Scaled 432 (Join-Path $Root 'icon_fg_432.png') 0.19
$src.Dispose()
$src = [System.Drawing.Image]::FromFile((Join-Path $Root 'art\icon_bg.png'))
Save-Scaled 432 (Join-Path $Root 'icon_bg_432.png')
$src.Dispose()
$src = $full
Copy-Item (Join-Path $Root 'icon_192.png') (Join-Path $Root 'docs\img\icon.png') -Force

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
