"""One-off patch of dist/Keys.ps1: key caps show what the real key prints (symbols, proper
names, a mouse picture) instead of three-letter codes."""
P = 'D:/i3-pc/dist/Keys.ps1'
s = open(P, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)


i = s.index("$caps = @{ leftbutton = 'LMB';")
j = s.index("# What an Xbox controller calls each PlayStation control")
s = s[:i] + '''# What each key shows on its cap. The game draws every icon in a fixed square cell, so a
# long name cannot get a wider cap: keys print what a real keyboard prints (the Shift arrow,
# a space-bar mark, the Enter and Tab arrows), short names in full, and mouse buttons a small
# mouse with that button filled. 'mouse:...' entries are drawn, the rest is text.
function Sym([int]$code) { return [string][char]$code }
$caps = @{ leftbutton = 'mouse:L'; rightbutton = 'mouse:R'; middlebutton = 'mouse:M';
    sidebuttonback = 'M4'; sidebuttonforward = 'M5'; mousewheelup = 'mouse:U';
    mousewheeldown = 'mouse:D'; space = (Sym 0x2423); enter = (Sym 0x23CE); escape = 'Esc';
    tab = (Sym 0x21E5); backspace = (Sym 0x232B); lshift = (Sym 0x21E7); rshift = (Sym 0x21E7);
    lctrl = 'Ctrl'; rctrl = 'Ctrl'; lalt = 'Alt'; ralt = 'Alt'; up = (Sym 0x2191);
    down = (Sym 0x2193); left = (Sym 0x2190); right = (Sym 0x2192); capslock = 'Caps';
    comma = ','; period = '.'; slash = '/'; semicolon = ';'; minus = '-'; equals = '=';
    pageup = 'PgUp'; pagedown = 'PgDn'; delete = 'Del'; insert = 'Ins'; home = 'Home';
    end = 'End' }

''' + s[j:]

rep("""                elseif ($cell[4].StartsWith('=')) { $cell[4].Substring(1) }""",
    """                elseif ($cell[4] -eq '=MSE') { 'mouse:' }
                elseif ($cell[4].StartsWith('=')) { $cell[4].Substring(1) }""")

rep("""        # Largest bold size whose text fits the cap.
        $fontSize = [float]($capHeight * 0.80)
        do {
            $font = New-Object System.Drawing.Font 'Arial Narrow', $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)""",
    """        if ($text.StartsWith('mouse:')) {
            # A mouse cut out of the cap: body outline, button divider, and the named button
            # (L, R, M) or wheel direction (U, D) cut out solid.
            $which = $text.Substring(6)
            $bw = [float]($capHeight * 0.50); $bh = [float]($capHeight * 0.74)
            $bx = [float]($x + ($w - $bw) / 2); $by = [float]($capY + ($capHeight - $bh) / 2)
            $r = [float]($bw / 2)
            $body = New-Object System.Drawing.Drawing2D.GraphicsPath
            $body.AddArc($bx, $by, $bw, $bw, 180, 180)
            $body.AddArc($bx, $by + $bh - $bw, $bw, $bw, 0, 180)
            $body.CloseFigure()
            $line = [float][Math]::Max(1.6, $capHeight * 0.055)
            $pen = New-Object System.Drawing.Pen $clear, $line
            $graphics.CompositingMode = 'SourceCopy'
            $graphics.DrawPath($pen, $body)
            $split = [float]($by + $bh * 0.42)
            $graphics.DrawLine($pen, $bx, $split, $bx + $bw, $split)
            $graphics.DrawLine($pen, $bx + $r, $by, $bx + $r, $split)
            $state = $graphics.Save()
            $graphics.SetClip($body)
            if ($which -eq 'L') { $graphics.FillRectangle($cut, $bx, $by, $r, $split - $by) }
            elseif ($which -eq 'R') { $graphics.FillRectangle($cut, $bx + $r, $by, $r, $split - $by) }
            elseif ($which) {
                $pw = [float]($bw * 0.30); $ph = [float]($bh * 0.30)
                $graphics.FillEllipse($cut, $bx + $r - $pw / 2, $by + $bh * 0.08, $pw, $ph)
            }
            $graphics.Restore($state)
            if ($which -eq 'U' -or $which -eq 'D') {
                # Wheel direction: a small arrow beside the mouse.
                $ax = [float]($bx + $bw + $capHeight * 0.10); $ay = [float]($by + $bh * 0.22)
                $as = [float]($capHeight * 0.16)
                $tri = if ($which -eq 'U') {
                    @((New-Object System.Drawing.PointF $ax, ($ay + $as)), (New-Object System.Drawing.PointF ($ax + $as), ($ay + $as)), (New-Object System.Drawing.PointF ($ax + $as / 2), $ay))
                } else {
                    @((New-Object System.Drawing.PointF $ax, $ay), (New-Object System.Drawing.PointF ($ax + $as), $ay), (New-Object System.Drawing.PointF ($ax + $as / 2), ($ay + $as)))
                }
                $graphics.FillPolygon($cut, [System.Drawing.PointF[]]$tri)
            }
            $pen.Dispose(); $body.Dispose(); $path.Dispose()
            continue
        }
        # Largest bold size whose text fits the cap. Symbols come from Segoe UI Symbol.
        $fontName = if ($text.Length -eq 1 -and [int][char]$text -gt 0x2000) { 'Segoe UI Symbol' } else { 'Arial Narrow' }
        $fontSize = [float]($capHeight * $(if ($fontName -eq 'Segoe UI Symbol') { 0.74 } else { 0.80 }))
        do {
            $font = New-Object System.Drawing.Font $fontName, $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)""")
open(P, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
