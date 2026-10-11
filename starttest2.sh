#!/bin/bash
# Second start-screen test (direct launch, ignores HOLD: only in an agreed slot).
# Part 1: Load Game on the start screen; the game's Options screen should open on "Load Game"
# by itself once the save has loaded. Part 2 (new start): Quit with its confirm step.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
run() { # seconds, script
    (env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_SCRIPT="$2" \
        "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    for ((i = 0; i < $1; i++)); do sleep 1; [ $i -gt 20 ] && [ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && break; done
    echo "ended by itself: $([ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && echo yes || echo no) after ${i}s"
    taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
}
# Load Game is the third row. The save needs about a minute; then 5 s, Options, two downs.
run 125 "40:key=down,41:key=down,43:key=enter,118:shotui"
# Quit is the last row: up from the first row wraps to it. First Enter arms, second quits.
run 75 "40:key=up,42:key=enter,44:shotui,46:key=enter"
n=0
for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st2_$n.png; done
echo "screenshots: $n"
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
