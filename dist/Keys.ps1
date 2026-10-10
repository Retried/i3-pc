# inFAMOUS Second Son - key bindings.
# Shows and changes the keyboard/mouse bindings in user\input_config\CUSA00004.ini and redraws
# the in-game button icons as key caps to match.
#   Keys.bat                      interactive menu
#   pwsh -File Keys.ps1 -List     print the bindings
#   pwsh -File Keys.ps1 -Set jump=space,melee=f      change bindings without the menu
#   pwsh -File Keys.ps1 -Icons    only redraw the icons from the current bindings
param(
    [switch]$List,
    [switch]$Icons,
    [string[]]$Set = @()
)

$ini = Join-Path $PSScriptRoot 'user\input_config\CUSA00004.ini'
$atlasSource = Join-Path $PSScriptRoot 'glyphs\atlas_original.raw'
$atlasHash = '7824aa19ec8ef328'
$packDir = Join-Path $PSScriptRoot 'user\sotc_textures\keyboard'

# Action name, pad output in the ini, what the game calls it.
$actions = @(
    @{ Name = 'attack';   Pad = 'r2';       Text = 'Main attack (R2)' }
    @{ Name = 'aim';      Pad = 'l2';       Text = 'Aim / zoom (L2)' }
    @{ Name = 'heavy';    Pad = 'r1';       Text = 'Heavy attack (R1)' }
    @{ Name = 'special';  Pad = 'l1';       Text = 'Special power (L1)' }
    @{ Name = 'jump';     Pad = 'cross';    Text = 'Jump (cross)' }
    @{ Name = 'dash';     Pad = 'circle';   Text = 'Dash (circle)' }
    @{ Name = 'melee';    Pad = 'square';   Text = 'Melee (square)' }
    @{ Name = 'karmic';   Pad = 'triangle'; Text = 'Karmic actions (triangle)' }
    @{ Name = 'touchpad'; Pad = 'touchpad_center'; Text = 'Touchpad press (drain, interact)' }
    @{ Name = 'l3';       Pad = 'l3';       Text = 'L3 (left stick click)' }
    @{ Name = 'r3';       Pad = 'r3';       Text = 'R3 (right stick click)' }
    @{ Name = 'pause';    Pad = 'options';  Text = 'Pause / options' }
    @{ Name = 'up';       Pad = 'pad_up';    Text = 'D-pad up' }
    @{ Name = 'down';     Pad = 'pad_down';  Text = 'D-pad down' }
    @{ Name = 'left';     Pad = 'pad_left';  Text = 'D-pad left' }
    @{ Name = 'right';    Pad = 'pad_right'; Text = 'D-pad right' }
    @{ Name = 'forward';  Pad = 'axis_left_y_minus'; Text = 'Move forward' }
    @{ Name = 'back';     Pad = 'axis_left_y_plus';  Text = 'Move back' }
    @{ Name = 'moveleft'; Pad = 'axis_left_x_minus'; Text = 'Move left' }
    @{ Name = 'moveright'; Pad = 'axis_left_x_plus'; Text = 'Move right' }
    @{ Name = 'sideways'; Pad = 'motion_sideways'; Text = 'Hold controller sideways (spray can)' }
    @{ Name = 'shake';    Pad = 'motion_shake';    Text = 'Shake controller' }
    @{ Name = 'swipeup';    Pad = 'touchpad_swipe_up';    Text = 'Touchpad swipe up' }
    @{ Name = 'swipedown';  Pad = 'touchpad_swipe_down';  Text = 'Touchpad swipe down' }
    @{ Name = 'swipeleft';  Pad = 'touchpad_swipe_left';  Text = 'Touchpad swipe left' }
    @{ Name = 'swiperight'; Pad = 'touchpad_swipe_right'; Text = 'Touchpad swipe right' }
    @{ Name = 'twofingers'; Pad = 'touchpad_two_fingers'; Text = 'Touchpad button with both thumbs (hold; Move Car)' }
)

# Key names the binding file accepts (letters and digits are themselves).
$named = @('space', 'enter', 'escape', 'tab', 'backspace', 'lshift', 'rshift', 'lctrl', 'rctrl',
    'lalt', 'ralt', 'up', 'down', 'left', 'right', 'leftbutton', 'rightbutton', 'middlebutton',
    'sidebuttonback', 'sidebuttonforward', 'mousewheelup', 'mousewheeldown', 'capslock',
    'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
    'kp0', 'kp1', 'kp2', 'kp3', 'kp4', 'kp5', 'kp6', 'kp7', 'kp8', 'kp9',
    'comma', 'period', 'slash', 'semicolon', 'minus', 'equals', 'home', 'end', 'insert', 'delete',
    'pageup', 'pagedown')
# Short text for a key cap.
# What each key shows on its cap. The game draws every icon in a fixed square cell, so a
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

# What an Xbox controller calls each PlayStation control (the icon sheet shown for Xbox pads).
$xboxNames = @{ r2 = 'RT'; l2 = 'LT'; r1 = 'RB'; l1 = 'LB'; r3 = 'RS'; l3 = 'LS'; cross = 'A';
    circle = 'B'; square = 'X'; triangle = 'Y'; options = 'MENU'; touchpad_center = 'VIEW';
    '=WASD' = 'LS'; '=MSE' = 'RS' }

function Test-Key($key) { return ($key -match '^[a-z0-9]$') -or ($named -contains $key) }

# A line binding a keyboard or mouse input: "<pad> = <key>" where the key is not a pad name.
$padNames = @('triangle', 'cross', 'square', 'circle', 'l1', 'l2', 'l3', 'r1', 'r2', 'r3', 'options',
    'back', 'pad_up', 'pad_down', 'pad_left', 'pad_right', 'axis_left_x', 'axis_left_y',
    'axis_right_x', 'axis_right_y', 'touchpad_left', 'touchpad_center', 'touchpad_right')

function Get-Bindings {
    $map = @{}
    foreach ($line in Get-Content $ini) {
        if ($line -match '^\s*([a-z0-9_]+)\s*=\s*([a-z0-9_]+)\s*$') {
            $pad = $Matches[1]; $key = $Matches[2]
            if ($padNames -contains $key) { continue }   # controller passthrough line
            if (-not $map.ContainsKey($pad)) { $map[$pad] = @() }
            $map[$pad] += $key
        }
    }
    return $map
}

function Set-Binding($pad, $keys) {
    $lines = [System.Collections.Generic.List[string]](Get-Content $ini)
    $first = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match "^\s*$pad\s*=\s*([a-z0-9_]+)\s*$" -and ($padNames -notcontains $Matches[1])) {
            $first = $i
            $lines.RemoveAt($i)
        }
    }
    if ($first -lt 0) {
        # Not bound before: put it ahead of the controller section.
        $first = 0
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^# --- Controller') { $first = $i; break } }
    }
    $new = @($keys | ForEach-Object { "$pad = $_" })
    $lines.InsertRange($first, [string[]]$new)
    Set-Content $ini $lines -Encoding ascii
}

function Show-Bindings {
    $map = Get-Bindings
    $n = 1
    foreach ($action in $actions) {
        $keys = if ($map[$action.Pad]) { $map[$action.Pad] -join ', ' } else { '(none)' }
        Write-Host ("{0,3}) {1,-38} {2,-11} {3}" -f $n, $action.Text, $action.Name, $keys)
        $n++
    }
}

function Get-Cap($pad, $map) {
    $key = if ($map[$pad]) { $map[$pad][0] } else { '' }
    if (-not $key) { return '?' }
    if ($caps.ContainsKey($key)) { return $caps[$key] }
    return $key.ToUpper()
}

# Redraws the game's 512x512 button-icon sheet with key caps in place of the pad buttons.
function Update-Icons([string]$Style = 'keyboard') {
    if (-not (Test-Path $atlasSource)) {
        Write-Host "Icon sheet not found ($atlasSource); icons left unchanged."
        return
    }
    Add-Type -AssemblyName System.Drawing
    $map = Get-Bindings
    $size = 512
    $bytes = [System.IO.File]::ReadAllBytes($atlasSource)
    # The sheet is stored bottom-up, RGBA. Work on an upright ARGB bitmap.
    $bitmap = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
    $data = $bitmap.LockBits($rect, 'WriteOnly', $bitmap.PixelFormat)
    $pixels = New-Object byte[] ($size * $size * 4)
    for ($y = 0; $y -lt $size; $y++) {
        $src = ($size - 1 - $y) * $size * 4
        $dst = $y * $size * 4
        for ($x = 0; $x -lt $size; $x++) {
            $pixels[$dst + 2] = $bytes[$src]; $pixels[$dst + 1] = $bytes[$src + 1]
            $pixels[$dst] = $bytes[$src + 2]; $pixels[$dst + 3] = $bytes[$src + 3]
            $src += 4; $dst += 4
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($pixels, 0, $data.Scan0, $pixels.Length)
    $bitmap.UnlockBits($data)

    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    $graphics.TextRenderingHint = 'AntiAliasGridFit'
    $clear = [System.Drawing.Color]::FromArgb(0, 255, 255, 255)
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $cut = New-Object System.Drawing.SolidBrush $clear
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'; $format.LineAlignment = 'Center'
    $format.FormatFlags = 'NoWrap'

    # Icon cells on the upright sheet: left, top, right, bottom, pad output (or fixed text).
    $cells = @(
        @(269, 8, 302, 41, 'r2'), @(320, 0, 369, 49, 'r3'), @(379, 8, 428, 41, 'touchpad_center'),
        @(435, 10, 490, 38, 'options'), @(299, 52, 344, 97, '=WASD'), @(358, 51, 406, 100, 'l3'),
        @(421, 51, 465, 98, '=MSE'), @(307, 154, 354, 201, 'r1'), @(358, 154, 405, 201, 'r2'),
        @(409, 154, 456, 201, 'l3'), @(460, 154, 507, 201, 'r3'), @(12, 220, 45, 253, 'l1'),
        @(71, 220, 104, 253, 'l2'), @(130, 220, 163, 253, 'r1'), @(181, 225, 230, 249, 'options'),
        @(240, 225, 289, 249, 'options'), @(6, 269, 43, 306, 'square'), @(57, 269, 94, 306, 'triangle'),
        @(108, 269, 145, 306, 'cross'), @(159, 269, 196, 306, 'circle'), @(205, 315, 252, 362, 'l1'),
        @(256, 315, 303, 362, 'l2')
    )
    foreach ($cell in $cells) {
        $x = $cell[0]; $y = $cell[1]; $w = $cell[2] - $cell[0] + 1; $h = $cell[3] - $cell[1] + 1
        $text = if ($Style -eq 'xbox') { $xboxNames[$cell[4]] }
                elseif ($cell[4] -eq '=MSE') { 'mouse:' }
                elseif ($cell[4].StartsWith('=')) { $cell[4].Substring(1) }
                else { Get-Cap $cell[4] $map }
        # Wipe the old icon, then a white key cap with the label cut out of it.
        $graphics.CompositingMode = 'SourceCopy'
        $graphics.FillRectangle($cut, $x - 1, $y - 1, $w + 2, $h + 2)
        $capHeight = [Math]::Min($h, [Math]::Max(26, [int]($h * 0.86)))
        $capY = $y + [int](($h - $capHeight) / 2)
        $radius = 6
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($x, $capY, $radius * 2, $radius * 2, 180, 90)
        $path.AddArc($x + $w - $radius * 2, $capY, $radius * 2, $radius * 2, 270, 90)
        $path.AddArc($x + $w - $radius * 2, $capY + $capHeight - $radius * 2, $radius * 2, $radius * 2, 0, 90)
        $path.AddArc($x, $capY + $capHeight - $radius * 2, $radius * 2, $radius * 2, 90, 90)
        $path.CloseFigure()
        $graphics.CompositingMode = 'SourceOver'
        $graphics.FillPath($white, $path)
        if ($text.StartsWith('mouse:')) {
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
        $fontSize = [float]($capHeight * $(if ($fontName -eq 'Segoe UI Symbol') { 0.94 } else { 0.80 }))
        do {
            $font = New-Object System.Drawing.Font $fontName, $fontSize, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
            $measured = $graphics.MeasureString($text, $font, 1000, $format)
            if ($measured.Width -le $w - 2 -or $fontSize -le 7) { break }
            $font.Dispose()
            $fontSize -= 1
        } while ($true)
        $textPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $box = New-Object System.Drawing.RectangleF $x, $capY, $w, $capHeight
        $textPath.AddString($text, $font.FontFamily, [int][System.Drawing.FontStyle]::Bold, $fontSize, $box, $format)
        $graphics.CompositingMode = 'SourceCopy'
        $graphics.FillPath($cut, $textPath)
        $font.Dispose(); $path.Dispose(); $textPath.Dispose()
    }
    $graphics.Dispose()

    # Back to bottom-up RGBA.
    $data = $bitmap.LockBits($rect, 'ReadOnly', $bitmap.PixelFormat)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
    $bitmap.UnlockBits($data)
    $out = New-Object byte[] ($size * $size * 4)
    for ($y = 0; $y -lt $size; $y++) {
        $src = $y * $size * 4
        $dst = ($size - 1 - $y) * $size * 4
        for ($x = 0; $x -lt $size; $x++) {
            $alpha = $pixels[$src + 3]
            # Transparent texels stay white so filtering does not darken the edges.
            if ($alpha -eq 0) { $out[$dst] = 255; $out[$dst + 1] = 255; $out[$dst + 2] = 255 }
            else { $out[$dst] = $pixels[$src + 2]; $out[$dst + 1] = $pixels[$src + 1]; $out[$dst + 2] = $pixels[$src] }
            $out[$dst + 3] = $alpha
            $src += 4; $dst += 4
        }
    }
    $target = Join-Path (Split-Path $packDir) $Style
    New-Item -ItemType Directory -Force $target | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $target "$atlasHash.bin"), $out)
    $bitmap.Save((Join-Path $PSScriptRoot "glyphs\${Style}_preview.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Write-Host "Button icons redrawn for $Style (preview: glyphs\${Style}_preview.png)."
}

function Apply-Change($name, $keyText) {
    $action = $actions | Where-Object { $_.Name -eq $name }
    if (-not $action) { Write-Host "Unknown action '$name'."; return $false }
    $keys = @($keyText.ToLower() -split '[ ,/]+' | Where-Object { $_ })
    foreach ($key in $keys) {
        if (-not (Test-Key $key)) { Write-Host "Unknown key '$key'. Letters, digits, or: $($named -join ' ')"; return $false }
    }
    Set-Binding $action.Pad $keys
    Write-Host ("{0}: {1}" -f $action.Text, ($keys -join ', '))
    return $true
}

if (-not (Test-Path $ini)) { Write-Host "Binding file not found: $ini"; exit 1 }

if ($List) { Show-Bindings; exit 0 }
if ($Icons) { Update-Icons keyboard; Update-Icons xbox; exit 0 }
if ($Set.Count) {
    $changed = $false
    foreach ($pair in ($Set -join ',') -split ',') {
        if ($pair -match '^\s*([a-z0-9]+)\s*=\s*(.+)$') { if (Apply-Change $Matches[1] $Matches[2]) { $changed = $true } }
    }
    if ($changed) { Update-Icons keyboard; Update-Icons xbox }
    exit 0
}

while ($true) {
    Write-Host ""
    Write-Host "inFAMOUS Second Son - key bindings"
    Show-Bindings
    Write-Host ""
    $choice = Read-Host "Number to change, or Enter to finish"
    if (-not $choice) { break }
    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $actions.Count) { continue }
    $action = $actions[[int]$choice - 1]
    Write-Host "Keys for '$($action.Text)': letters, digits, or names such as space, lshift, lctrl, tab,"
    Write-Host "leftbutton, rightbutton, middlebutton, mousewheelup, up, f1... Several keys: separate with spaces."
    $keys = Read-Host "New key(s), or Enter to keep"
    if ($keys) { [void](Apply-Change $action.Name $keys) }
}
Update-Icons keyboard
Update-Icons xbox
Write-Host "Done. In a running game press F8 to reload bindings; icons change on the next start."
