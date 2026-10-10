#!/bin/bash
# Unpaused: Hank arena, aim and fire smoke shots for three minutes. ./shootsoak.sh <label> [VAR=..]
cd /d/i3-pc || exit 1
label=$1; shift
until [ "$(tasklist | grep -ci -E 'ffmpeg|ShadowOfTheColossus|shadps4')" = "0" ] && [ ! -f HOLD ]; do sleep 15; done
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/defeathank-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 400 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done
until grep -q "Flip: fps [3-9][0-9]" testrun/user/log/shad_log.txt 2>/dev/null; do sleep 5; done; sleep 30
F=testrun/live_cmds.txt; L=testrun/user/log/shad_log.txt
for i in $(seq 1 90); do
    echo "key=rightbutton*1400" >> $F; sleep 0.35
    for j in 1 2 3; do echo "key=leftbutton*90" >> $F; sleep 0.33; done
    [ $((i % 6)) = 0 ] && echo "mouse=30*600" >> $F
    sleep 0.6
    if [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; then echo "$label: DIED after $((i*2)) s"; break; fi
done
echo "$label: alive $(tasklist | grep -ci '^i3.exe') dropped $(grep -c 'Dropped indirect' $L)"
grep -a "Unhandled\|Critical\|Assert\|terminate" $L | tail -4 | cut -c1-300
tail -3 $L | cut -c1-220
echo quit >> $F; sleep 8
