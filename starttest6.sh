#!/bin/bash
# Menu test for the layout with one Options entry (direct launch, ignores HOLD: only in an
# agreed slot). Boot 1: start screen, Options page, Graphics, back, Continue with the pad;
# pause menu, Options page and the game's own Options through it, all with the pad.
# Boot 2: New Game on the start screen with saves present.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
run() { # seconds, script
    (env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_VPAD=1 SOTC_SCRIPT="$2" \
        "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    sleep "$1"; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
}
a="38:shotui,39:key=down,40:key=down,41:key=down,42:key=enter,44:shotui,45:key=enter,47:shotui"
a="$a,48:key=escape,49:key=escape,51:pad=south"
a="$a,112:pad=start,114:shotui,115:pad=dpdown,116:pad=south,118:shotui,119:pad=dpdown,120:pad=dpdown,121:pad=south,126:shotui"
run 131 "$a"
run 122 "40:key=down,42:key=enter,116:shotui"
n=0
for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st6_$n.png; done
echo "screenshots: $n"
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
