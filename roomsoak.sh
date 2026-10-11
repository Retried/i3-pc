#!/bin/bash
# No pauses at all: from the inside-cannery checkpoint through both timber barriers into the
# burned room, then stay there. ./roomsoak.sh <label> [VAR=value ...]
cd /d/i3-pc || exit 1
label=$1; shift
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/insidecannery-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 700 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
F=testrun/live_cmds.txt; L=testrun/user/log/shad_log.txt
k() { echo "$1" >> $F; sleep "$2"; }
k "key=w*2500" 2.7; echo "key=lshift" >> $F; k "key=w*2500" 2.7; k "key=w*2500" 2.7; sleep 40
for i in 1 2 3 4 5 6; do k "key=f" 1.0; done; k "key=w*2500" 2.7
for i in 1 2 3 4 5 6; do k "key=f" 1.0; done; k "key=w*2500" 2.7; k "key=w*1500" 1.7
k shot 2; cp "$(ls -t testrun/user/screenshots/*.png | head -1)" tools/roomsoak_$label.png
for i in 1 2 3 4 5 6 7 8 9 10; do
    k "mouse=30*1300" 1.5; k "key=w*800" 1; k "key=f" 1; k "key=s*800" 26.5
    alive=$(tasklist | grep -ci '^i3.exe')
    echo "$label t=$((i*30))s dropped $(grep -c 'Dropped indirect' $L) alive $alive lost $(grep -c 'GPU ops' $L) fps $(grep 'Flip: fps' $L | tail -1 | awk '{print $7}')"
    [ "$alive" = "0" ] && break
done
k shot 2; cp "$(ls -t testrun/user/screenshots/*.png | head -1)" tools/roomsoak_${label}_end.png
echo quit >> $F; sleep 8
