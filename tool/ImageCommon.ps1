#Requires -Version 5.1
<#
.SYNOPSIS
    System.Drawing helpers shared by the icon and store-asset generators.

.DESCRIPTION
    Dot-source this from a generator script:

        . (Join-Path $PSScriptRoot 'ImageCommon.ps1')

    flutter_launcher_icons and the Dart `image` package are deliberately not
    used: `image` needs xml ^6 or archive ^4 and cannot co-exist with this
    project's xml ^7 / archive ^3 constraints.
#>
Add-Type -AssemblyName System.Drawing

function Get-OpaqueBounds {
    <#
    .SYNOPSIS
        Returns a centred square rectangle covering the bitmap's opaque pixels.
    #>
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
    if ($maxX -lt 0) { throw 'Source image is fully transparent.' }

    # Expand to a centred square so the artwork is never distorted.
    $cx   = ($minX + $maxX) / 2.0
    $cy   = ($minY + $maxY) / 2.0
    $half = [Math]::Max($maxX - $minX + 1, $maxY - $minY + 1) / 2.0
    $side = [int][Math]::Round($half * 2)
    return New-Object System.Drawing.Rectangle `
        ([int][Math]::Round($cx - $half)), ([int][Math]::Round($cy - $half)), $side, $side
}

function Save-Png {
    param([System.Drawing.Bitmap]$Bitmap, [string]$Path)

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}
