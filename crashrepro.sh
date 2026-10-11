#!/bin/bash
# Reproduces the route to the "Stay with Reggie" failure and the checkpoint reload after it,
# then keeps playing for a while. ./crashrepro.sh [VAR=value ...] -> says whether the game survived.
cd /d/i3-pc || exit 1
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 0; }
./livestart.sh 900 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
s() { /d/i3-pc/stepper.sh "$@" > /dev/null; }
route() {
    for i in 1 2 3 4; do s 2.6 "key=w*2500"; done; s 1.6 "key=w*3000" "key=lshift"
    for i in 1 2 3; do s 2.6 "key=w*2500"; done; s 1.8 "key=w*3000" "key=space"
    for i in 1 2 3; do s 2.6 "key=w*2500"; done; s 1.6 "key=w*3000" "key=lshift"
    for i in 1 2 3; do s 2.6 "key=w*2500"; done; s 1.5 "key=w*3000" "key=lshift"
}
s 0; route
s 2.1 "key=w*2000"; s 1.4 "key=d*1200"; s 2.6 "key=w*2500"; s 2.6 "key=w*2500"; s 1.0 "key=a*800"; s 1.3 "key=w*1200"
s 1.2 "mouse=30*500"; s 1.2 "mouse=30*500"; s 1.8 "mouse=30*1300"
for i in 1 2 3 4 5; do s 2.6 "key=w*2500"; done   # leaves Reggie: mission fails, checkpoint reloads
s 6; s 3; route; s 2.1 "key=w*2000"; s 5; s 5
if [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; then echo "CRASHED"; grep "Unhandled Exception" testrun/user/log/shad_log.txt | cut -c60-200
else echo "survived"; echo resume >> testrun/live_cmds.txt; echo quit >> testrun/live_cmds.txt; sleep 8; fi
