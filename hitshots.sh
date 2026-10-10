#!/bin/bash
# Unpaused: to the first timber barrier, screenshots right after each hit. ./hitshots.sh <label> [VAR=..]
cd /d/i3-pc || exit 1
label=$1; shift
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/insidecannery-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin} ./livestart.sh 300 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
F=testrun/live_cmds.txt; L=testrun/user/log/shad_log.txt
k() { echo "$1" >> $F; sleep "$2"; }
k "key=w*2500" 2.7; echo "key=lshift" >> $F; k "key=w*2500" 2.7; k "key=w*2500" 2.7; sleep 40
n=0
for i in 1 2 3 4; do k "key=f" 0.45; k shot 0.9; n=$((n+1)); cp "$(ls -t testrun/user/screenshots/*.png | head -1)" tools/hit_${label}_$n.png; done
echo "$label dropped $(grep -c 'Dropped indirect' $L) alive $(tasklist | grep -ci '^i3.exe') lost $(grep -c 'GPU ops' $L)"
echo quit >> $F; sleep 8
