#Requires -Version 5.1
<#
.SYNOPSIS
    Regenerates the Android and Windows launcher icons from design/logo.png.

.DESCRIPTION
    Run this after replacing design/logo.png:

        pwsh tool/generate_app_icons.ps1

    Produces:
      android/app/src/main/res/mipmap-*/ic_launcher.png             legacy icon (full bleed)
      android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  adaptive foreground (108dp canvas)
      android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml    adaptive icon definition
      android/app/src/main/res/values/ic_launcher_background.xml    adaptive background colour
      windows/runner/resources/app_icon.ico                         multi-resolution Windows icon

    flutter_launcher_icons is deliberately not used: it depends on `image`,
    which needs xml ^6 or archive ^4 and cannot co-exist with this project's
    xml ^7 / archive ^3 constraints.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root       = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'design\logo.png'
$resDir     = Join-Path $root 'android\app\src\main\res'
$icoPath    = Join-Path $root 'windows\runner\resources\app_icon.ico'

# Adaptive-icon background. Matches the near-black ring of the artwork so the
# ring blends into the mask on circular launchers.
$adaptiveBackground = '#0B0806'

# Android reserves the outer edge of the 108dp adaptive canvas for parallax and
# masking; only the central 72dp circle is guaranteed visible.
$foregroundScale = 72.0 / 108.0

# density => @(legacy icon px, 108dp foreground canvas px)
$densities = [ordered]@{
    'mdpi'    = @(48, 108)
    'hdpi'    = @(72, 162)
    'xhdpi'   = @(96, 216)
    'xxhdpi'  = @(144, 324)
    'xxxhdpi' = @(192, 432)
}

$icoSizes = @(16, 24, 32, 48, 64, 128, 256)

function Get-OpaqueBounds {
    param([System.Drawing.Bitmap]$Bitmap)

    $rect = New-Object System.Drawing.Rectangle 0, 0, $Bitmap.Width, $Bitmap.Height
    $data = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                             [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $buffer = New-Object byte[] ($data.Stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buffer, 0, $buffer.Length)
    } finally {
        $Bitmap.UnlockBits($data)
    }

    $minX = $Bitmap.Width; $minY = $Bitmap.Height; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        $row = $y * $data.Stride
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($buffer[$row + $x * 4 + 3] -gt 8) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    if ($maxX -lt 0) { throw "$sourcePath is fully transparent." }

    # Expand to a centred square so the artwork is never distorted.
    $cx   = ($minX + $maxX) / 2.0
    $cy   = ($minY + $maxY) / 2.0
    $half = [Math]::Max($maxX - $minX + 1, $maxY - $minY + 1) / 2.0
    $side = [int][Math]::Round($half * 2)
    return New-Object System.Drawing.Rectangle `
        ([int][Math]::Round($cx - $half)), ([int][Math]::Round($cy - $half)), $side, $side
}

function New-ScaledIcon {
    param(
        [System.Drawing.Bitmap]$Source,
        [System.Drawing.Rectangle]$SourceRect,
        [int]$CanvasSize,
        [double]$Scale = 1.0
    )

    $target = New-Object System.Drawing.Bitmap $CanvasSize, $CanvasSize,
                         ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $target.SetResolution(96, 96)
    $g = [System.Drawing.Graphics]::FromImage($target)
    try {
        $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)

        $drawn  = [int][Math]::Round($CanvasSize * $Scale)
        $offset = [int][Math]::Round(($CanvasSize - $drawn) / 2.0)
        $dest   = New-Object System.Drawing.Rectangle $offset, $offset, $drawn, $drawn

        # TileFlipXY stops the bicubic kernel from sampling transparent black
        # outside the source rect, which would darken the edge of the disc.
        $attrs = New-Object System.Drawing.Imaging.ImageAttributes
        try {
            $attrs.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $g.DrawImage($Source, $dest, $SourceRect.X, $SourceRect.Y,
                         $SourceRect.Width, $SourceRect.Height,
                         [System.Drawing.GraphicsUnit]::Pixel, $attrs)
        } finally {
            $attrs.Dispose()
        }
    } finally {
        $g.Dispose()
    }
    return $target
}

function Save-Png {
    param([System.Drawing.Bitmap]$Bitmap, [string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function ConvertTo-IcoDib {
    param([System.Drawing.Bitmap]$Bitmap)

    # An ICO "DIB" entry is a BITMAPINFOHEADER with a doubled height, followed
    # by bottom-up BGRA pixels and a 1bpp AND mask. For 32bpp entries Windows
    # keys off the alpha channel, so the AND mask is left all-zero (opaque).
    $w = $Bitmap.Width
    $h = $Bitmap.Height

    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                             [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $pixels = New-Object byte[] ($data.Stride * $h)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
        $stride = $data.Stride
    } finally {
        $Bitmap.UnlockBits($data)
    }

    $maskStride = [int][Math]::Floor(($w + 31) / 32) * 4
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    try {
        $bw.Write([uint32]40)          # biSize
        $bw.Write([int32]$w)           # biWidth
        $bw.Write([int32]($h * 2))     # biHeight: colour data + AND mask
        $bw.Write([uint16]1)           # biPlanes
        $bw.Write([uint16]32)          # biBitCount
        $bw.Write([uint32]0)           # biCompression: BI_RGB
        $bw.Write([uint32]($w * 4 * $h + $maskStride * $h))  # biSizeImage
        $bw.Write([int32]0)            # biXPelsPerMeter
        $bw.Write([int32]0)            # biYPelsPerMeter
        $bw.Write([uint32]0)           # biClrUsed
        $bw.Write([uint32]0)           # biClrImportant

        for ($y = $h - 1; $y -ge 0; $y--) {
            $bw.Write($pixels, $y * $stride, $w * 4)
        }
        $bw.Write((New-Object byte[] ($maskStride * $h)))

        $bw.Flush()
        # Unary comma: without it PowerShell unrolls the byte[] into the pipeline.
        return , $ms.ToArray()
    } finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

function Save-Ico {
    param(
        [System.Drawing.Bitmap]$Source,
        [System.Drawing.Rectangle]$SourceRect,
        [int[]]$Sizes,
        [string]$Path
    )

    # Sizes below 256 are stored as uncompressed DIBs and 256 as PNG, matching
    # what the Windows resource compiler and LoadIcon handle everywhere.
    # System.Drawing.Icon in particular cannot read PNG entries under 256.
    $frames = @()
    foreach ($size in $Sizes) {
        $bmp = New-ScaledIcon -Source $Source -SourceRect $SourceRect -CanvasSize $size
        try {
            if ($size -ge 256) {
                $ms = New-Object System.IO.MemoryStream
                try {
                    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $frames += , $ms.ToArray()
                } finally { $ms.Dispose() }
            } else {
                $frames += , ([byte[]](ConvertTo-IcoDib -Bitmap $bmp))
            }
        } finally { $bmp.Dispose() }
    }

    $stream = [System.IO.File]::Create($Path)
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0)             # reserved
        $writer.Write([uint16]1)             # type: icon
        $writer.Write([uint16]$Sizes.Count)

        $offset = 6 + 16 * $Sizes.Count
        for ($i = 0; $i -lt $Sizes.Count; $i++) {
            $dim = if ($Sizes[$i] -ge 256) { 0 } else { $Sizes[$i] }  # 0 means 256
            $writer.Write([byte]$dim)        # width
            $writer.Write([byte]$dim)        # height
            $writer.Write([byte]0)           # palette size
            $writer.Write([byte]0)           # reserved
            $writer.Write([uint16]1)         # colour planes
            $writer.Write([uint16]32)        # bits per pixel
            $writer.Write([uint32]$frames[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write($frame) }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$source = New-Object System.Drawing.Bitmap($sourcePath)
try {
    Write-Host "Source: $sourcePath ($($source.Width)x$($source.Height))"
    $bounds = Get-OpaqueBounds -Bitmap $source
    Write-Host "Trimmed to $($bounds.Width)x$($bounds.Height) at ($($bounds.X),$($bounds.Y))"

    foreach ($density in $densities.Keys) {
        $legacySize     = $densities[$density][0]
        $foregroundSize = $densities[$density][1]

        $legacy = New-ScaledIcon -Source $source -SourceRect $bounds -CanvasSize $legacySize
        try { Save-Png $legacy (Join-Path $resDir "mipmap-$density\ic_launcher.png") }
        finally { $legacy.Dispose() }

        $foreground = New-ScaledIcon -Source $source -SourceRect $bounds `
                                     -CanvasSize $foregroundSize -Scale $foregroundScale
        try { Save-Png $foreground (Join-Path $resDir "mipmap-$density\ic_launcher_foreground.png") }
        finally { $foreground.Dispose() }

        Write-Host "  mipmap-$density : ic_launcher ${legacySize}px, ic_launcher_foreground ${foregroundSize}px"
    }

    $anydpi = Join-Path $resDir 'mipmap-anydpi-v26'
    if (-not (Test-Path $anydpi)) { New-Item -ItemType Directory -Path $anydpi -Force | Out-Null }

    $adaptiveXml = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'@
    Set-Content -Path (Join-Path $anydpi 'ic_launcher.xml') -Value $adaptiveXml -Encoding UTF8

    $backgroundXml = @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$adaptiveBackground</color>
</resources>
"@
    Set-Content -Path (Join-Path $resDir 'values\ic_launcher_background.xml') -Value $backgroundXml -Encoding UTF8

    Write-Host '  mipmap-anydpi-v26/ic_launcher.xml + values/ic_launcher_background.xml'

    Save-Ico -Source $source -SourceRect $bounds -Sizes $icoSizes -Path $icoPath
    Write-Host "  $icoPath ($($icoSizes -join ', '))"
} finally {
    $source.Dispose()
}

Write-Host 'Done.'
