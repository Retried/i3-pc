"""One-off patch of dist/Keys.ps1: a keyboard-and-mouse diagram replaces the controller picture
on the game's Options screen while keyboard prompts are shown."""
P = 'D:/i3-pc/dist/Keys.ps1'
s = open(P, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')

BLOCK = r'''# ---- Controls diagram of the game's Options screen ----
# The game shows a picture of a controller with leader lines running out to its action labels
# (one 1024x512 texture, BC3, stored bottom-up; the labels are the game's own text). While
# keyboard prompts are shown that texture is replaced by a drawing made here: the same lines,
# ending in key caps that name the bound keys in full.
$diagramHash = '85b798ad24996118'
$longNames = @{ leftbutton = 'Left mouse'; rightbutton = 'Right mouse'; middlebutton = 'Middle mouse';
    sidebuttonback = 'Mouse 4'; sidebuttonforward = 'Mouse 5'; mousewheelup = 'Wheel up';
    mousewheeldown = 'Wheel down'; space = 'Space'; enter = 'Enter'; escape = 'Esc'; tab = 'Tab';
    backspace = 'Backspace'; lshift = 'Shift'; rshift = 'Right Shift'; lctrl = 'Ctrl';
    rctrl = 'Right Ctrl'; lalt = 'Alt'; ralt = 'Right Alt'; up = 'Up'; down = 'Down'; left = 'Left';
    right = 'Right'; capslock = 'Caps Lock'; comma = ','; period = '.'; slash = '/'; semicolon = ';';
    minus = '-'; equals = '='; pageup = 'Page Up'; pagedown = 'Page Down'; delete = 'Delete';
    insert = 'Insert'; home = 'Home'; end = 'End' }

function Get-LongName($pad, $map, [int]$most = 2) {
    if (-not $map[$pad]) { return '-' }
    $names = @($map[$pad] | Select-Object -First $most | ForEach-Object {
        if ($longNames.ContainsKey($_)) { $longNames[$_] } else { $_.ToUpper() } })
    return ($names -join ' / ')
}

$bc3Source = @'
using System;
public static class I3Bc3 {
    static int To565(int r, int g, int b) { return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3); }
    // BGRA rows, top first, to BC3 blocks (bounding-box end points, nearest palette entry).
    public static byte[] Encode(byte[] bgra, int width, int height) {
        int bw = (width + 3) / 4, bh = (height + 3) / 4;
        byte[] result = new byte[bw * bh * 16];
        int[] pr = new int[16], pg = new int[16], pb = new int[16], pa = new int[16];
        int[] pal = new int[8];
        for (int by = 0; by < bh; by++) {
            for (int bx = 0; bx < bw; bx++) {
                int minA = 255, maxA = 0, minR = 255, minG = 255, minB = 255, maxR = 0, maxG = 0, maxB = 0;
                for (int i = 0; i < 16; i++) {
                    int x = Math.Min(bx * 4 + (i & 3), width - 1), y = Math.Min(by * 4 + (i >> 2), height - 1);
                    int o = (y * width + x) * 4;
                    pb[i] = bgra[o]; pg[i] = bgra[o + 1]; pr[i] = bgra[o + 2]; pa[i] = bgra[o + 3];
                    minA = Math.Min(minA, pa[i]); maxA = Math.Max(maxA, pa[i]);
                    minR = Math.Min(minR, pr[i]); maxR = Math.Max(maxR, pr[i]);
                    minG = Math.Min(minG, pg[i]); maxG = Math.Max(maxG, pg[i]);
                    minB = Math.Min(minB, pb[i]); maxB = Math.Max(maxB, pb[i]);
                }
                int at = (by * bw + bx) * 16;
                result[at] = (byte)maxA; result[at + 1] = (byte)minA;
                ulong bits = 0;
                if (maxA != minA) {
                    pal[0] = maxA; pal[1] = minA;
                    for (int k = 1; k < 7; k++) pal[k + 1] = ((7 - k) * maxA + k * minA) / 7;
                    for (int i = 0; i < 16; i++) {
                        int best = 0, bestError = 1000;
                        for (int k = 0; k < 8; k++) {
                            int error = Math.Abs(pal[k] - pa[i]);
                            if (error < bestError) { bestError = error; best = k; }
                        }
                        bits |= (ulong)best << (3 * i);
                    }
                }
                for (int k = 0; k < 6; k++) result[at + 2 + k] = (byte)(bits >> (8 * k));
                int c0 = To565(maxR, maxG, maxB), c1 = To565(minR, minG, minB);
                result[at + 8] = (byte)c0; result[at + 9] = (byte)(c0 >> 8);
                result[at + 10] = (byte)c1; result[at + 11] = (byte)(c1 >> 8);
                uint colourBits = 0;
                if (c0 != c1) {
                    for (int i = 0; i < 16; i++) {
                        int best = 0, bestError = int.MaxValue;
                        for (int k = 0; k < 4; k++) {
                            int wa = k == 0 ? 3 : k == 1 ? 0 : k == 2 ? 2 : 1;
                            int r = (wa * maxR + (3 - wa) * minR) / 3, g = (wa * maxG + (3 - wa) * minG) / 3;
                            int b = (wa * maxB + (3 - wa) * minB) / 3;
                            int error = (r - pr[i]) * (r - pr[i]) + (g - pg[i]) * (g - pg[i]) + (b - pb[i]) * (b - pb[i]);
                            if (error < bestError) { bestError = error; best = k; }
                        }
                        colourBits |= (uint)best << (2 * i);
                    }
                }
                for (int k = 0; k < 4; k++) result[at + 12 + k] = (byte)(colourBits >> (8 * k));
            }
        }
        return result;
    }
}
'@

function Update-Diagram {
    Add-Type -AssemblyName System.Drawing
    if (-not ('I3Bc3' -as [type])) { Add-Type -TypeDefinition $bc3Source }
    $map = Get-Bindings
    $w = 1024; $h = 512
    $bitmap = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $clear = [System.Drawing.Color]::FromArgb(0, 255, 255, 255)
    $g.Clear($clear)
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $cut = New-Object System.Drawing.SolidBrush $clear
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235, 255, 255, 255)), 2.5
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'; $format.LineAlignment = 'Center'; $format.FormatFlags = 'NoWrap'

    $move = @('axis_left_y_minus', 'axis_left_x_minus', 'axis_left_y_plus', 'axis_left_x_plus' |
        ForEach-Object { if ($map[$_]) { Get-LongName $_ $map 1 } else { '-' } }) -join ' '
    # Side, height of the game's leader line on the texture, cap text. The heights are where
    # the game's labels sit: Zoom, Special Power, Move, Turn on the left; Main Attack, Heavy
    # Attack, Karmic Actions, Dash, Jump, Melee on the right.
    $rows = @(
        @('L', 83, (Get-LongName 'l2' $map)), @('L', 163, (Get-LongName 'l1' $map)),
        @('L', 388, $move), @('L', 439, 'Mouse'),
        @('R', 80, (Get-LongName 'r2' $map)), @('R', 151, (Get-LongName 'r1' $map)),
        @('R', 221, (Get-LongName 'triangle' $map)), @('R', 290, (Get-LongName 'circle' $map)),
        @('R', 361, (Get-LongName 'cross' $map)), @('R', 431, (Get-LongName 'square' $map))
    )
    foreach ($row in $rows) {
        $left = $row[0] -eq 'L'; $y = [int]$row[1]; $text = [string]$row[2]
        $capH = 46
        $fontSize = [float]30
        do {
            $font = New-Object System.Drawing.Font 'Segoe UI', $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
            $capW = [int][Math]::Max($capH, $g.MeasureString($text, $font, 2000, $format).Width + 22)
            if ($capW -le 250 -or $fontSize -le 14) { break }
            $font.Dispose(); $fontSize -= 1
        } while ($true)
        $inner = if ($left) { 252 } else { 772 }
        $capX = if ($left) { $inner } else { $inner - $capW }
        $capY = $y - [int]($capH / 2)
        $g.CompositingMode = 'SourceOver'
        if ($left) { $g.DrawLine($pen, 0, $y, $inner, $y) } else { $g.DrawLine($pen, $inner, $y, $w - 1, $y) }
        $radius = 9
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($capX, $capY, $radius * 2, $radius * 2, 180, 90)
        $path.AddArc($capX + $capW - $radius * 2, $capY, $radius * 2, $radius * 2, 270, 90)
        $path.AddArc($capX + $capW - $radius * 2, $capY + $capH - $radius * 2, $radius * 2, $radius * 2, 0, 90)
        $path.AddArc($capX, $capY + $capH - $radius * 2, $radius * 2, $radius * 2, 90, 90)
        $path.CloseFigure()
        $g.FillPath($white, $path)
        $textPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $box = New-Object System.Drawing.RectangleF $capX, ($capY - 1), $capW, $capH
        $textPath.AddString($text, $font.FontFamily, [int][System.Drawing.FontStyle]::Bold, $fontSize, $box, $format)
        $g.CompositingMode = 'SourceCopy'
        $g.FillPath($cut, $textPath)
        $font.Dispose(); $path.Dispose(); $textPath.Dispose()
    }
    $g.Dispose()
    New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'glyphs') | Out-Null
    $bitmap.Save((Join-Path $PSScriptRoot 'glyphs\diagram_preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)

    # The whole mip chain, each level bottom-up, as BC3.
    $out = New-Object System.IO.MemoryStream
    $lw = $w; $lh = $h
    while ($true) {
        $level = New-Object System.Drawing.Bitmap $lw, $lh, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $lg = [System.Drawing.Graphics]::FromImage($level)
        $lg.CompositingMode = 'SourceCopy'
        $lg.InterpolationMode = 'HighQualityBicubic'
        $lg.PixelOffsetMode = 'HighQuality'
        $lg.DrawImage($bitmap, (New-Object System.Drawing.Rectangle 0, 0, $lw, $lh), 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel)
        $lg.Dispose()
        $level.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipY)
        $data = $level.LockBits((New-Object System.Drawing.Rectangle 0, 0, $lw, $lh), 'ReadOnly', $level.PixelFormat)
        $pixels = New-Object byte[] ($lw * $lh * 4)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
        $level.UnlockBits($data); $level.Dispose()
        $blocks = [I3Bc3]::Encode($pixels, $lw, $lh)
        $out.Write($blocks, 0, $blocks.Length)
        if ($lw -eq 1 -and $lh -eq 1) { break }
        $lw = [Math]::Max(1, [int][Math]::Floor($lw / 2)); $lh = [Math]::Max(1, [int][Math]::Floor($lh / 2))
    }
    $bitmap.Dispose()
    New-Item -ItemType Directory -Force $packDir | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $packDir "$diagramHash.bin"), $out.ToArray())
    Write-Host 'Controls diagram redrawn for keyboard and mouse (preview: glyphs\diagram_preview.png).'
}

'''

a = '# Redraws the game\'s 512x512 button-icon sheet with key caps in place of the pad buttons.\n'
assert s.count(a) == 1
s = s.replace(a, BLOCK + a)
a = "function Update-Icons([string]$Style = 'keyboard') {\n"
assert s.count(a) == 1
s = s.replace(a, a + "    # The diagram needs nothing from the game, so it is drawn even without the icon sheet.\n"
                     "    if ($Style -eq 'keyboard') { Update-Diagram }\n")
open(P, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
