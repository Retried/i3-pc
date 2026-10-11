#!/bin/bash
# Start screen and pause menu test, one scripted session started directly (it does not wait on
# the HOLD file: run it only in an agreed slot). Screenshots land in tools/st_*.png.
# Return to Main Menu starts the program again; the second start replays the script from its
# beginning, which shows the start screen once more before the session is ended.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
script="40:shotui,43:key=down,44:key=down,45:key=down,47:shotui,48:key=up,49:key=up,50:key=up,52:key=enter"
script="$script,112:key=escape,115:shotui,117:key=down,119:key=enter,124:shotui,126:key=lshift"
script="$script,130:key=escape,133:key=up,135:key=enter,137:shotui,139:key=enter"
(env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_SCRIPT="$script" \
    "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
sleep 188
taskkill //IM i3.exe //F > /dev/null 2>&1
sleep 2
echo "left running: $(tasklist | grep -ci '^i3.exe')"
n=0
for f in $(ls -tr user/screenshots/*.png); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st_$n.png; done
echo "screenshots: $n"
grep -a -c "returning to the start screen" user/log/shad_log.txt
grep -a "Unhandled\|Assert" user/log/shad_log.txt | tail -2 | cut -c1-200
