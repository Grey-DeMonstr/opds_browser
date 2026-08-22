#Requires -Version 5.1
<#
.SYNOPSIS
    Regenerates the Google Play store graphics from design/logo.png.

.DESCRIPTION
    Run this after replacing design/logo.png:

        pwsh tool/generate_play_assets.ps1

    Produces:
      design/play/icon-512.png                    512x512 store icon, opaque
      design/play/feature-graphic-1024x500.png    1024x500 feature graphic, opaque

    These are STORE assets, not app assets. They are not bundled into the AAB;
    they are uploaded to the Play Console by hand.

    Both are composited opaque over the brand background: Play applies its own
    mask to the icon and should not be handed an alpha channel.

    The feature graphic is functional rather than designed - flat background,
    logo, wordmark. It is adequate to pass review and is expected to be
    replaced by hand later, like the screenshots.

    flutter_launcher_icons and the Dart `image` package are deliberately not
    used: `image` needs xml ^6 or archive ^4 and cannot co-exist with this
    project's xml ^7 / archive ^3 constraints.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'ImageCommon.ps1')

$root       = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'design\logo.png'
$outDir     = Join-Path $root 'design\play'

# Same near-black as the adaptive-icon background in generate_app_icons.ps1.
$brandBackground = '#0B0806'
$wordmarkColour  = '#E8DCC8'
$wordmarkText    = 'OPDS Browser'

if (-not (Test-Path $sourcePath)) { throw "Not found: $sourcePath" }

function New-Canvas {
    param([int]$Width, [int]$Height, [string]$BackgroundHex)

    $bmp = New-Object System.Drawing.Bitmap $Width, $Height,
                     ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.ColorTranslator]::FromHtml($BackgroundHex))
    } finally {
        $g.Dispose()
    }
    return $bmp
}

function Add-Logo {
    <#
    .SYNOPSIS
        Draws $Source's $SourceRect into $Target as a square of $Size pixels,
        with its top-left corner at ($X, $Y).
    #>
    param(
        [System.Drawing.Bitmap]$Target,
        [System.Drawing.Bitmap]$Source,
        [System.Drawing.Rectangle]$SourceRect,
        [int]$X, [int]$Y, [int]$Size
    )

    $g = [System.Drawing.Graphics]::FromImage($Target)
    try {
        $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $dest = New-Object System.Drawing.Rectangle $X, $Y, $Size, $Size

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
}

function Add-Wordmark {
    param(
        [System.Drawing.Bitmap]$Target,
        [string]$Text,
        [string]$ColourHex,
        [single]$FontSize,
        [single]$X, [single]$CentreY
    )

    $g = [System.Drawing.Graphics]::FromImage($Target)
    $font  = $null
    $brush = $null
    try {
        $g.TextRenderingHint =
            [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        # Segoe UI is present on every supported Windows build. System.Drawing
        # silently substitutes a default face when a family is missing, so pick
        # one that is certain to exist rather than a decorative one.
        $font  = New-Object System.Drawing.Font 'Segoe UI', $FontSize,
                            ([System.Drawing.FontStyle]::Bold),
                            ([System.Drawing.GraphicsUnit]::Pixel)
        $brush = New-Object System.Drawing.SolidBrush(
                            [System.Drawing.ColorTranslator]::FromHtml($ColourHex))

        $size = $g.MeasureString($Text, $font)
        $g.DrawString($Text, $font, $brush, $X, $CentreY - $size.Height / 2.0)
    } finally {
        if ($brush) { $brush.Dispose() }
        if ($font)  { $font.Dispose() }
        $g.Dispose()
    }
}

$source = New-Object System.Drawing.Bitmap $sourcePath
try {
    $bounds = Get-OpaqueBounds -Bitmap $source

    # --- 512x512 store icon -------------------------------------------------
    # Play masks the icon, so leave a margin: the artwork fills 84% of the side.
    $icon = New-Canvas -Width 512 -Height 512 -BackgroundHex $brandBackground
    try {
        $iconArt = [int][Math]::Round(512 * 0.84)
        $iconOff = [int][Math]::Round((512 - $iconArt) / 2.0)
        Add-Logo -Target $icon -Source $source -SourceRect $bounds `
                 -X $iconOff -Y $iconOff -Size $iconArt
        Save-Png -Bitmap $icon -Path (Join-Path $outDir 'icon-512.png')
    } finally {
        $icon.Dispose()
    }

    # --- 1024x500 feature graphic -------------------------------------------
    # Play crops and overlays this in several places, so keep everything well
    # inside the frame rather than bleeding to the edges.
    $feature = New-Canvas -Width 1024 -Height 500 -BackgroundHex $brandBackground
    try {
        $logoSize = 300
        $logoX    = 96
        $logoY    = [int][Math]::Round((500 - $logoSize) / 2.0)
        Add-Logo -Target $feature -Source $source -SourceRect $bounds `
                 -X $logoX -Y $logoY -Size $logoSize
        Add-Wordmark -Target $feature -Text $wordmarkText `
                     -ColourHex $wordmarkColour -FontSize 60 `
                     -X 452 -CentreY 250
        Save-Png -Bitmap $feature `
                 -Path (Join-Path $outDir 'feature-graphic-1024x500.png')
    } finally {
        $feature.Dispose()
    }
} finally {
    $source.Dispose()
}

Write-Host "Wrote store assets to $outDir"
