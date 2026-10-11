#!/bin/bash
# Starts a paused live session and replays the route from the post-cutscene save to the
# overturned car (after the car-throw scene). ./route.sh [seconds]
cd /d/i3-pc || exit 1
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 1; }
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh "${1:-1200}" "45:cross,60:cross" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
s() { /d/i3-pc/stepper.sh "$@" > /dev/null; }
s 0
for i in 1 2 3 4; do s 2.6 "key=w*2500"; done; s 1.6 "key=w*3000" "key=lshift"
for i in 1 2 3; do s 2.6 "key=w*2500"; done; s 1.8 "key=w*3000" "key=space"
for i in 1 2 3; do s 2.6 "key=w*2500"; done; s 1.6 "key=w*3000" "key=lshift"
for i in 1 2 3; do s 2.6 "key=w*2500"; done; s 1.5 "key=w*3000" "key=lshift"
s 2.1 "key=w*2000"
echo "at the car"
