#!/bin/bash
# What does one fragment shader draw in the slow Seattle view, and what does it cost? Reaches
# the view like cityview.sh, takes a screenshot, skips the shader's draws ("skipfs="), waits,
# takes another and prints the frame rate before and after. Optimized build.
#   ./cityskip.sh <fragment shader hash, hex>     pictures: tools/cityskip_before.png, _after.png
cd /d/i3-pc || exit 1
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
L=testrun/user/log/shad_log.txt; F=testrun/live_cmds.txt
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/seattle-CUSA00004 $S/CUSA00004
cp tools/gfx.bak testrun/user/i3_graphics.txt
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 300 "45:cross,60:cross" > /dev/null; sleep ${WAIT:-115}
for step in $(seq 1 13); do echo "mouse=30*600" >> $F; sleep 4; done
rate() { grep -a "Flip: fps" $L | tail -4 | sed 's/.*Flip: fps //' | awk -v l="$1" '{s+=$1; n++} END {printf "%s: %.1f FPS\n", l, s/n}'; }
grab() { echo shot >> $F; sleep 2; new=$(ls -t testrun/user/screenshots/*.png | head -1); ffmpeg -y -loglevel error -i "$new" -vf scale=960:-1 tools/cityskip_$1.png; }
sleep 14; rate before; grab before
echo "skipfs=$1" >> $F; sleep 16; rate "without $1"; grab after
grep -a "stats/3s" $L | tail -1 | sed 's/.*Tick: //'
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
