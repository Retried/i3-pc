#!/bin/bash
# New Game from the start screen with the keyboard: one Down from Continue, Enter, then game
# screenshots as the opening plays (tools/ng_N.png). Test profile only. Optimized build unless
# BIN is set. Direct launch: only in an agreed slot.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/${FX:-seattle}-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png ../tools/ng_[0-9].png
a="20:shotui,21:key=down,22:shotui,23:key=enter,45:shotui,70:shotui,100:shotui,130:shotui"
(env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_SCRIPT="$a" \
    "${BIN:-/d/i3-pc/bin-release}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
sleep 200; echo quit >> live_cmds.txt; sleep 6; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
n=0; for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" ../tools/ng_$n.png; done
echo "screenshots: $n"
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
