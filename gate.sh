#!/bin/bash
# Paused live session from the fishcannery fixture, replayed through the cannery gate into the
# yard and around the crates ("ENTER FISH CANNERY"). ./gate.sh [seconds]
cd /d/i3-pc || exit 1
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/fishcannery-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh "${1:-1700}" "45:cross,60:cross" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
s() { /d/i3-pc/stepper.sh "$@" > /dev/null; }
s 0; s 2.1 "key=w*2000"; s 1.2 "mouse=30*800"; for i in 1 2 3; do s 2.6 "key=w*2500"; done
s 1.2 "mouse=30*700"; for i in 1 2 3; do s 3.1 "key=w*3000"; done; s 1.0 "mouse=30*500"; s 3.1 "key=w*3000"
s 0.8 "mouse=30*250"; s 2.1 "key=w*2000"; s 2.1 "key=w*2000"; s 0.8 "mouse=30*350"; s 1.9 "key=w*1700"
s 0.9 "key=s*600"; s 1.5 "key=d*1200"; s 0.8 "key=s*400"; s 0.8 "key=a*500"; s 0.8 "key=s*400"; s 0.8 "key=a*500"
s 1.6 "key=w*2500" "key=lshift"; s 1.6 "key=w*2500" "key=lshift"; s 3
for i in 1 2 3; do s 1.6 "mouse=-30*1300"; done
for i in 1 2 3; do s 3.1 "key=w*3000"; done; s 0.8 "key=s*500"; s 2.6 "key=d*2400"; s 3.1 "key=w*3000"
echo "in the yard"
