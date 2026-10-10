#!/bin/bash
# From the inside-cannery checkpoint to the "Press F to hit the timbers" prompt, then F.
# ./melee.sh [VAR=value ...] -> says whether the game survived; counts dropped indirect draws.
cd /d/i3-pc || exit 1
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/insidecannery-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 600 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
L=/d/i3-pc/testrun/user/log/shad_log.txt
s() { /d/i3-pc/stepper.sh "$@" > /dev/null; }
s 0; cp tools/live.png tools/m0.png
s 2.6 "key=w*2500"; s 1.6 "key=w*2500" "key=lshift"; s 2.6 "key=w*2500"
for i in 1 2 3 4 5; do s 8; done; cp tools/live.png tools/m1.png
echo "before F: dropped $(grep -c 'Dropped indirect' $L), alive $(tasklist | grep -ci '^i3.exe')"
s 1.2 "key=f"; cp tools/live.png tools/m2.png
echo "after F 1: dropped $(grep -c 'Dropped indirect' $L), alive $(tasklist | grep -ci '^i3.exe')"
s 1.2 "key=f"; s 1.2 "key=f"; s 3; cp tools/live.png tools/m3.png
echo "after F 3: dropped $(grep -c 'Dropped indirect' $L), alive $(tasklist | grep -ci '^i3.exe')"
grep -c "Device lost\|GPU ops" $L
tools/venv/Scripts/python -c "
from PIL import Image
c=Image.new('RGB',(1920,1080))
for i in range(4): c.paste(Image.open('D:/i3-pc/tools/m%d.png'%i),((i%2)*960,(i//2)*540))
c.save('D:/i3-pc/tools/pair.png')"
