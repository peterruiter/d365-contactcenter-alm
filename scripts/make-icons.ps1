<#
.SYNOPSIS
    Draws the product icon and writes every size the local runner's exe and the XrmToolBox tool need.
.DESCRIPTION
    One drawing, every size: the brand blue rounded square with "CC" and an arrow, meaning
    configuration moving from one environment to the next.

      runner-exe/icon.ico                          16, 20, 24, 32, 48, 64, 128 and 256 px, for the
                                                   exe, Explorer, the taskbar and the file details
      xrmtoolbox/src/CcAlm.XrmToolBox/Icons.cs     32 and 80 px, as base64, for the tool list
      xrmtoolbox/icon.png                          128 px, the package icon on nuget.org and in
                                                   the XrmToolBox Tool Library

    Each size is drawn at four times its size and scaled down, so small ones stay sharp. The .ico
    holds PNG frames, which Windows has read since Vista.
.EXAMPLE
    ./scripts/make-icons.ps1
#>
#Requires -Version 7.2
param(
    # Draw the icon and show where the files would go, without writing them.
    [switch] $WhatIfOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$blue = [System.Drawing.ColorTranslator]::FromHtml('#0070AD')
$white = [System.Drawing.Color]::White

function New-RoundedRectPath([float] $x, [float] $y, [float] $w, [float] $h, [float] $r) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# One frame of the icon, drawn big and scaled down to $size.
function New-IconBitmap([int] $size) {
    $scale = 4
    $c = $size * $scale
    $big = [System.Drawing.Bitmap]::new($c, $c, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($big)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([System.Drawing.Color]::Transparent)

        # The square itself.
        $inset = [float]($c * 0.02)
        $side = [float]($c - 2 * $inset)
        $square = New-RoundedRectPath $inset $inset $side $side ([float]($c * 0.22))
        $brush = [System.Drawing.SolidBrush]::new($blue)
        $g.FillPath($brush, $square)
        $brush.Dispose()
        $square.Dispose()

        # Below 32 px the arrow is a smear, so those sizes carry the letters alone, bigger.
        $tiny = $size -lt 32

        # "CC", as an outline so it scales exactly.
        $family = [System.Drawing.FontFamily]::new('Segoe UI')
        $text = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $format = [System.Drawing.StringFormat]::new()
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $box = if ($tiny) { [System.Drawing.RectangleF]::new(0, 0, [float]$c, [float]$c) }
               else { [System.Drawing.RectangleF]::new(0, [float]($c * 0.05), [float]$c, [float]($c * 0.62)) }
        $em = if ($tiny) { [float]($c * 0.58) } else { [float]($c * 0.45) }
        $text.AddString('CC', $family, [int][System.Drawing.FontStyle]::Bold, $em, $box, $format)
        $textBrush = [System.Drawing.SolidBrush]::new($white)
        $g.FillPath($textBrush, $text)
        $text.Dispose()
        $format.Dispose()
        $family.Dispose()

        # The arrow underneath: configuration moving to the next environment.
        $barLeft = [float]($c * 0.21)
        $barRight = [float]($c * 0.60)
        $headTip = [float]($c * 0.79)
        $midY = [float]($c * 0.745)
        $barHalf = [float]($c * 0.058)
        $headHalf = [float]($c * 0.135)
        $arrow = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $arrow.AddPolygon([System.Drawing.PointF[]] @(
            [System.Drawing.PointF]::new($barLeft, $midY - $barHalf),
            [System.Drawing.PointF]::new($barRight, $midY - $barHalf),
            [System.Drawing.PointF]::new($barRight, $midY - $headHalf),
            [System.Drawing.PointF]::new($headTip, $midY),
            [System.Drawing.PointF]::new($barRight, $midY + $headHalf),
            [System.Drawing.PointF]::new($barRight, $midY + $barHalf),
            [System.Drawing.PointF]::new($barLeft, $midY + $barHalf)
        ))
        if (-not $tiny) { $g.FillPath($textBrush, $arrow) }
        $arrow.Dispose()
        $textBrush.Dispose()
    }
    finally { $g.Dispose() }

    $small = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gs = [System.Drawing.Graphics]::FromImage($small)
    try {
        $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gs.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gs.Clear([System.Drawing.Color]::Transparent)
        $gs.DrawImage($big, [System.Drawing.Rectangle]::new(0, 0, $size, $size))
    }
    finally { $gs.Dispose(); $big.Dispose() }
    return $small
}

function Get-PngBytes([System.Drawing.Bitmap] $bitmap) {
    $stream = [System.IO.MemoryStream]::new()
    try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    }
    finally { $stream.Dispose() }
}

# ICONDIR, one ICONDIRENTRY per size, then the PNG frames.
function Write-Ico([string] $path, [int[]] $sizes) {
    $frames = foreach ($size in $sizes) {
        $bitmap = New-IconBitmap $size
        try { [pscustomobject]@{ Size = $size; Bytes = Get-PngBytes $bitmap } } finally { $bitmap.Dispose() }
    }
    $out = [System.IO.MemoryStream]::new()
    $w = [System.IO.BinaryWriter]::new($out)
    try {
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($f in $frames) {
            $w.Write([byte]($f.Size -band 0xFF))   # 256 is written as 0
            $w.Write([byte]($f.Size -band 0xFF))
            $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]$f.Bytes.Length); $w.Write([uint32]$offset)
            $offset += $f.Bytes.Length
        }
        $w.Flush()
        # Straight to the stream: BinaryWriter.Write would bind a byte array to another overload.
        foreach ($f in $frames) { $out.Write($f.Bytes, 0, $f.Bytes.Length) }
        [System.IO.File]::WriteAllBytes($path, $out.ToArray())
    }
    finally { $w.Dispose(); $out.Dispose() }
}

function Get-Base64([int] $size) {
    $bitmap = New-IconBitmap $size
    try { return [Convert]::ToBase64String((Get-PngBytes $bitmap)) } finally { $bitmap.Dispose() }
}

$icoPath = Join-Path $root 'runner-exe/icon.ico'
$iconsCs = Join-Path $root 'xrmtoolbox/src/CcAlm.XrmToolBox/Icons.cs'
$pngPath = Join-Path $root 'xrmtoolbox/icon.png'
if ($WhatIfOnly) {
    Write-Host "Would write $icoPath, $iconsCs and $pngPath." -ForegroundColor Yellow
    return
}

Write-Ico $icoPath @(16, 20, 24, 32, 48, 64, 128, 256)

$csharp = @"
namespace CcAlm.XrmToolBox
{
    /// <summary>
    /// The tool's icons for the XrmToolBox tool list (32 and 80 px PNG). Generated by
    /// scripts/make-icons.ps1, which draws the same icon as the local runner's exe.
    /// </summary>
    static class Icons
    {
        public const string Small = "$(Get-Base64 32)";

        public const string Big = "$(Get-Base64 80)";
    }
}
"@
Set-Content -Path $iconsCs -Value $csharp -Encoding utf8NoBOM

$package = New-IconBitmap 128
try { $package.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $package.Dispose() }

$size = [math]::Round((Get-Item $icoPath).Length / 1KB, 1)
Write-Host "Wrote $icoPath ($size KB), $iconsCs and $pngPath." -ForegroundColor Green
