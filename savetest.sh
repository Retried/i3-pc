#!/bin/bash
# Loads a fixture through Continue and takes screenshots while it runs. Direct launch (ignores
# HOLD: only in an agreed slot). ./savetest.sh <label> <fixture> [seconds]
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
label=$1; secs=${3:-200}
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/$2-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
(env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 \
    SOTC_SCRIPT="45:cross,60:cross,90:shot,110:shot,130:shot,150:shot,170:shot,190:shot" \
    "${BIN:-/d/i3-pc/bin-release}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
for ((i = 0; i < secs; i++)); do sleep 1; [ $i -gt 30 ] && [ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && break; done
echo "$label: ran ${i}s, alive $(tasklist | grep -ci '^i3.exe'), fps $(grep -a 'Flip: fps' user/log/shad_log.txt | tail -1 | awk '{print $7}')"
taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
n=0
for f in $(ls -tr user/screenshots/*.png 2>/dev/null); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/sv_${label}_$n.png; done
echo "$label: screenshots $n"
grep -a "Unhandled\|Assert\|world_\|msn_" user/log/shad_log.txt | tail -4 | cut -c1-200
cp -rp $S/CUSA00004 /d/i3-pc/tools/sv_${label}_after 2>/dev/null
