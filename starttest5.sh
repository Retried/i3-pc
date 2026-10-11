#!/bin/bash
# Fifth menu test (direct launch, ignores HOLD: only in an agreed slot).
# Part 1: New Game on the start screen with saves present (keyboard): the game's Options screen
# should open on "New Game" once the save has loaded.
# Part 2: the menus driven by a controller (virtual pad): d-pad, cross, Options, circle.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
run() { # seconds, script, extra env
    (env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 $3 SOTC_SCRIPT="$2" \
        "${BIN:-/d/i3-pc/bin-release}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    sleep "$1"; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
}
run 122 "40:key=down,42:key=enter,116:shotui"
# Pad: down twice then up twice (back on Continue), cross; in play Options opens the pause
# menu, down once, screenshot, circle closes it, screenshot of the running game.
run 128 "38:pad=dpdown,39:pad=dpdown,40:shotui,41:pad=dpup,42:pad=dpup,43:pad=south,110:pad=start,113:pad=dpdown,115:shotui,117:pad=east,121:shotui" "SOTC_VPAD=1"
n=0
for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st5_$n.png; done
echo "screenshots: $n"
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
