#!/bin/bash
# Third start-screen test (direct launch, ignores HOLD: only in an agreed slot).
# Part 1: a profile without saves: what the start screen offers and what New Game does.
# Part 2: with a save: the pause menu, to check that no "Emulation Paused" label shows.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata
rm -f user/screenshots/*.png
run() { # seconds, script
    (env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_SCRIPT="$2" \
        "${BIN:-/d/i3-pc/bin-release}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    sleep "$1"; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
}
rm -rf $S/CUSA00004
run 80 "38:shotui,41:key=enter,58:shotui,74:shotui"
rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
run 120 "40:key=enter,108:key=escape,112:shotui,114:key=escape"
n=0
for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st3_$n.png; done
echo "screenshots: $n"
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
