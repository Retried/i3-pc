#!/bin/bash
# Menu test for the restyled menus, the Options sections and controller navigation (direct
# launch, ignores HOLD: only in an agreed slot). Test binary by default.
# Boot 1, virtual pad only: start screen, Options, Graphics (scrolled), back, Controls, back,
# back, Continue; in play: pause, Options, Sound pass-through (the game's screen on Sound).
# Boot 2, keyboard: Achievements page, then New Game with saves present.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
run() { # seconds, script
    (env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_VPAD=1 SOTC_SCRIPT="$2" \
        "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    sleep "$1"; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
}
# Start screen rows with saves: Continue, New Game, Load Game, Options, Achievements, Quit.
a="38:shotui,39:pad=dpdown,40:pad=dpdown,41:pad=dpdown,42:pad=a,44:shotui"
# Options page: Graphics is first. Open it, go down 12 rows, screenshot, back.
a="$a,45:pad=a,47:shotui"
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do a="$a,$((48 + i)):pad=dpdown"; done
a="$a,61:shotui,62:pad=b,63:pad=dpdown,64:pad=a,66:shotui,67:pad=b,68:pad=b"
# Back on the start screen at the top: Continue.
a="$a,70:shotui,71:pad=a"
# In play: pause, screenshot, Options (second row), Sound (fourth row), wait for the game's screen.
a="$a,134:pad=start,136:shotui,137:pad=dpdown,138:pad=a,139:pad=dpdown,140:pad=dpdown,141:pad=dpdown,142:shotui,143:pad=a,152:shotui"
run 190 "$a"; cp user/log/shad_log.txt /d/i3-pc/tools/st7_boot1.log
b="38:key=down,39:key=down,40:key=down,41:key=down,42:key=enter,44:shotui,45:key=escape"
b="$b,46:key=up,47:key=up,48:key=up,49:key=enter,122:shotui"
run 160 "$b"
n=0
for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st7_$n.png; done
echo "screenshots: $n"
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
