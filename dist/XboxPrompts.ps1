# SPDX-License-Identifier: GPL-2.0-or-later
# Original procedural glyphs for the verified CUSA00004 button atlas cells.
# No game atlas, controller artwork or SDK assets are required.
param([string]$OutputDirectory = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Upright bounds from Keys.ps1; leave touchpad, motion and unverified cells intact.
$cells = @(
    @(269, 8, 302, 41, 'RT'), @(320, 0, 369, 49, 'RS'),
    @(435, 10, 490, 38, 'Menu'), @(299, 52, 344, 97, 'LS'),
    @(358, 51, 406, 100, 'LS'), @(421, 51, 465, 98, 'RS'),
    @(307, 154, 354, 201, 'RB'), @(358, 154, 405, 201, 'RT'),
    @(409, 154, 456, 201, 'LS'), @(460, 154, 507, 201, 'RS'),
    @(12, 220, 45, 253, 'LB'), @(71, 220, 104, 253, 'LT'),
    @(130, 220, 163, 253, 'RB'), @(181, 225, 230, 249, 'Menu'),
    @(240, 225, 289, 249, 'Menu'), @(6, 269, 43, 306, 'X'),
    @(57, 269, 94, 306, 'Y'), @(108, 269, 145, 306, 'A'),
    @(159, 269, 196, 306, 'B'), @(205, 315, 252, 362, 'LB'),
    @(256, 315, 303, 362, 'LT')
)
$pack = Join-Path $OutputDirectory 'user\sotc_textures\xbox'
$previews = Join-Path $OutputDirectory 'glyphs'
New-Item -ItemType Directory -Force $pack, $previews | Out-Null
$stream = [IO.MemoryStream]::new()
$writer = [IO.BinaryWriter]::new($stream)
$writer.Write([Text.Encoding]::ASCII.GetBytes('I3P1'))
$writer.Write([uint32]512); $writer.Write([uint32]512); $writer.Write([uint32]$cells.Count)
$preview = [Drawing.Bitmap]::new(512, 512)
$previewGraphics = [Drawing.Graphics]::FromImage($preview)
$previewGraphics.Clear([Drawing.Color]::Transparent)
$white = [Drawing.Brushes]::White
$clear = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(0, 255, 255, 255))
$format = [Drawing.StringFormat]::new()
$format.Alignment = 'Center'; $format.LineAlignment = 'Center'; $format.FormatFlags = 'NoWrap'
try {
    foreach ($cell in $cells) {
        $x = $cell[0]; $y = $cell[1]
        $w = $cell[2] + 1 - $x; $h = $cell[3] + 1 - $y; $label = $cell[4]
        $bitmap = [Drawing.Bitmap]::new($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($bitmap)
        $g.Clear([Drawing.Color]::FromArgb(0, 255, 255, 255))
        $g.SmoothingMode = 'AntiAlias'
        $g.PixelOffsetMode = 'HighQuality'
        $box = [Drawing.RectangleF]::new(2, 2, ($w - 4), ($h - 4))
        $path = [Drawing.Drawing2D.GraphicsPath]::new()
        if ($label -in @('A', 'B', 'X', 'Y', 'LS', 'RS')) {
            $d = [Math]::Min($box.Width, $box.Height)
            $box = [Drawing.RectangleF]::new((($w - $d) / 2), (($h - $d) / 2), $d, $d)
            $path.AddEllipse($box)
        } else {
            $r = [float]6
            $path.AddArc($box.X, $box.Y, $r * 2, $r * 2, 180, 90)
            $path.AddArc($box.Right - $r * 2, $box.Y, $r * 2, $r * 2, 270, 90)
            $path.AddArc($box.Right - $r * 2, $box.Bottom - $r * 2, $r * 2, $r * 2, 0, 90)
            $path.AddArc($box.X, $box.Bottom - $r * 2, $r * 2, $r * 2, 90, 90)
            $path.CloseFigure()
        }
        $g.FillPath($white, $path)
        $g.CompositingMode = 'SourceCopy'
        if ($label -eq 'Menu') {
            $barW = [float]($box.Width * 0.42); $barH = [float]2
            foreach ($fraction in @(0.30, 0.50, 0.70)) {
                $g.FillRectangle($clear, [float](($w - $barW) / 2),
                    [float]($box.Y + $box.Height * $fraction - 1), $barW, $barH)
            }
        } else {
            $fontSize = [float]($box.Height * 0.70)
            do {
                $font = [Drawing.Font]::new('Arial', $fontSize, [Drawing.FontStyle]::Bold,
                    [Drawing.GraphicsUnit]::Pixel)
                if ($g.MeasureString($label, $font).Width -le $box.Width * 0.88 -or $fontSize -le 7) { break }
                $font.Dispose(); $fontSize -= 1
            } while ($true)
            $letters = [Drawing.Drawing2D.GraphicsPath]::new()
            $letters.AddString($label, $font.FontFamily, [int][Drawing.FontStyle]::Bold,
                $fontSize, $box, $format)
            $g.FillPath($clear, $letters)
            $letters.Dispose(); $font.Dispose()
        }
        $g.Dispose(); $path.Dispose()
        $previewGraphics.DrawImageUnscaled($bitmap, $x, $y)
        $rect = [Drawing.Rectangle]::new(0, 0, $w, $h)
        $bits = $bitmap.LockBits($rect, 'ReadOnly', $bitmap.PixelFormat)
        $bgra = [byte[]]::new($bits.Stride * $h)
        [Runtime.InteropServices.Marshal]::Copy($bits.Scan0, $bgra, 0, $bgra.Length)
        $bitmap.UnlockBits($bits); $bitmap.Dispose()
        $rgba = [byte[]]::new($w * $h * 4)
        for ($row = 0; $row -lt $h; $row++) {
            for ($col = 0; $col -lt $w; $col++) {
                $src = $row * $bits.Stride + $col * 4
                $dst = (($h - 1 - $row) * $w + $col) * 4
                $rgba[$dst] = 255; $rgba[$dst + 1] = 255; $rgba[$dst + 2] = 255
                $rgba[$dst + 3] = $bgra[$src + 3]
            }
        }
        $writer.Write([uint32]$x); $writer.Write([uint32](512 - $y - $h))
        $writer.Write([uint32]$w); $writer.Write([uint32]$h); $writer.Write($rgba)
    }
    [IO.File]::WriteAllBytes((Join-Path $pack '7824aa19ec8ef328.patch'), $stream.ToArray())
    $preview.Save((Join-Path $previews 'xbox_preview.png'), [Drawing.Imaging.ImageFormat]::Png)
    # Remove only the legacy generated Xbox atlas, which mislabeled the touchpad as View.
    $legacy = Join-Path $pack '7824aa19ec8ef328.bin'
    if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy }
} finally {
    $writer.Dispose(); $stream.Dispose(); $previewGraphics.Dispose(); $preview.Dispose()
    $clear.Dispose(); $format.Dispose()
}
Write-Output "Xbox prompt patches generated: $pack"
