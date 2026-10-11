#!/bin/bash
# Unpaused: from the catch-hank checkpoint through the doors into the Hank fight, then stay
# while Hank attacks. Screenshots every 4 s. ./hank.sh <label> [VAR=value ...]
cd /d/i3-pc || exit 1
label=$1; shift
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/catchhank-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin} ./livestart.sh 400 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
F=testrun/live_cmds.txt; L=testrun/user/log/shad_log.txt
k() { echo "$1" >> $F; sleep "$2"; }
k "key=w*2500" 2.7; echo "key=lshift" >> $F; k "key=w*2500" 2.7; k "key=w*2500" 2.7; sleep 45
k "skipfs=f8eafe6c" 0.5; rm -f tools/hank_${label}_*.png
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    k "key=rightbutton*1500" 0.3; k "key=leftbutton" 1.7; k shot 2
    cp "$(ls -t testrun/user/screenshots/*.png | head -1)" tools/hank_${label}_$i.png
    [ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && break
done
echo "$label dropped $(grep -c 'Dropped indirect' $L) alive $(tasklist | grep -ci '^i3.exe') lost $(grep -c 'GPU ops' $L) fps $(grep 'Flip: fps' $L | tail -1 | awk '{print $7}')"
echo quit >> $F; sleep 8
