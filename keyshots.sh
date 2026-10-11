#!/bin/bash
# Menu screenshots with keyboard hints: one boot without the virtual controller; start screen,
# Options, Graphics (tools/ks_N.png). Optimized build. Direct launch: only in an agreed slot.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
rm -f user/screenshots/*.png ../tools/ks_*.png
a="20:shotui,21:key=down,22:key=down,23:key=down,24:key=enter,26:shotui,27:key=enter,29:shotui,30:key=down,32:shotui"
(env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_SCRIPT="$a" \
    "${BIN:-/d/i3-pc/bin-release}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
sleep 120; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
n=0; for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" ../tools/ks_$n.png; done
echo "screenshots: $n"
