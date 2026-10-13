#!/bin/bash
# Render-thread profile of the slow view in Seattle: test build with the stack sampler, Seattle
# save, the camera turns right in small steps until the frame rate falls under LIMIT (40 by
# default), then holds that view for 35 seconds. Prints the frame rate, the runtime's time
# lines and the profile summary; keeps a screenshot (tools/cityprof.png) and the profile
# (tools/cityprof_profile.txt). Direct launch: only in an agreed slot.
cd /d/i3-pc || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/seattle-CUSA00004 $S/CUSA00004
rm -f testrun/profile_full.txt
BIN=/d/i3-pc/bin ./livestart.sh 420 "45:cross,60:cross" SOTC_PROFILE=1 "$@" > /dev/null; sleep 200
F=testrun/live_cmds.txt; L=testrun/user/log/shad_log.txt
rate() { grep -a "Flip: fps" $L | tail -1 | sed 's/.*Flip: fps //; s/ .*//'; }
for step in $(seq 1 30); do
    echo "mouse=30*600" >> $F; sleep 4
    r=$(rate); echo "step $step: $r fps"
    [ "$(awk -v r="$r" -v l="${LIMIT:-40}" 'BEGIN {print (r < l) ? 1 : 0}')" = "1" ] && break
done
sleep 35
echo shot >> $F; sleep 2
grep -a "Flip: fps" $L | tail -4 | sed 's/.*Flip: //' | tr '\n' ';'; echo
grep -a "cpu/3s\|time/3s" $L | tail -2 | sed 's/.*Tick: //'
cp testrun/profile_full.txt tools/cityprof_profile.txt
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
new=$(ls -t testrun/user/screenshots/*.png 2>/dev/null | head -1)
[ -n "$new" ] && ffmpeg -y -loglevel error -i "$new" -vf scale=640:-1 tools/cityprof.png
tools/venv/Scripts/python tools/symprof.py 30 2>&1 | cut -c1-140
