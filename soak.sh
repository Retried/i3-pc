#!/bin/bash
# Soak inside the burning cannery: ./soak.sh <label> [VAR=value ...]
# Plays to the first timber hits, then idles for 6 minutes, printing dropped indirect draws.
cd /d/i3-pc || exit 1
label=$1; shift
./melee.sh "$@" > /dev/null 2>&1 || { echo "$label: could not start"; exit 1; }
L=/d/i3-pc/testrun/user/log/shad_log.txt
echo resume >> testrun/live_cmds.txt
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 30
    alive=$(tasklist | grep -ci '^i3.exe')
    echo "$label t=$((i*30))s dropped $(grep -c 'Dropped indirect' $L) alive $alive lost $(grep -c 'GPU ops' $L) fps $(grep 'Flip: fps' $L | tail -1 | awk '{print $7}')"
    [ "$alive" = "0" ] && break
done
echo quit >> testrun/live_cmds.txt; sleep 8
