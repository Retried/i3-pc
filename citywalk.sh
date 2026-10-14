#!/bin/bash
# The same short run through Seattle every time (save fixtures/edit-sp: free in the city), with
# the freeze log on: frame rate every 3 s, freezes, pipeline compile time, and how many stored
# pipelines could not be used ("conflicts"). Optimized build.   ./citywalk.sh <label>
cd /d/i3-pc || exit 1
label=$1
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/edit-sp-CUSA00004 $S/CUSA00004
cp tools/gfx.bak testrun/user/i3_graphics.txt
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 330 "45:cross,60:cross" I3_FREEZELOG=1 > /dev/null; sleep 125
F=testrun/live_cmds.txt
for i in $(seq 1 12); do
    echo "key=w*4000" >> $F; sleep 0.4; echo "key=lshift*300" >> $F; sleep 1.6
    echo "key=space*300" >> $F; sleep 1.2; echo "mouse=30*500" >> $F; sleep 1.5
done
L=testrun/user/log/shad_log.txt; cp $L tools/citywalk_$label.log
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
grep -a "Flip: fps" $L | sed 's/.*Flip: fps //' | awk '{printf "%s/%s ", int($1), $3} END {print ""}' | cut -c1-400
echo "$label: freezes $(grep -a -c 'freeze [0-9]* ms' $L), pipeline compile ms $(grep -a -o 'pipeline compile [0-9]*' $L | awk '{s+=$3} END {print s+0}'), compiled pipelines $(grep -a -c 'Compiling graphics pipeline\|Compiling compute pipeline' $L), conflicts $(grep -a -c 'conflicts with index' $L), unhandled $(grep -a -c Unhandled $L)"
