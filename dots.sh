#!/bin/bash
# Aim mapping: dab paint at a grid of (yaw,pitch) angles. ./dots.sh out.png "<yaws>" "<pitches>" [VAR=value ...]
cd /d/i3-pc || exit 1
out=$1; yaws=$2; pitches=$3; shift 3
until [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; do sleep 3; done
./livestart.sh ${SECS:-300} "45:cross,60:cross,75:cross,95:cross" I3_AIM_MAX=3 "$@" > /dev/null
sleep 20; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 80
[ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && { echo "session died"; tail -3 livestart.log; exit 1; }
./live.sh "key=g*250000" wait=5 > /dev/null; ./live.sh "key=h*4000" wait=10 > /dev/null
F=testrun/live_cmds.txt; n=0
for p in $pitches; do
    echo "key=h*1500" >> $F; sleep 1.8
    for y in $yaws; do echo "aim=$y,$p" >> $F; sleep 0.25; echo "key=leftbutton*500" >> $F; sleep 0.8; done
    ./live.sh wait=0.1 > /dev/null; cp tools/live.png tools/dot$n.png; n=$((n+1))
done
echo quit >> $F
tools/venv/Scripts/python - "$out" $n <<'PY'
import sys
from PIL import Image
n = int(sys.argv[2]); s = Image.new('RGB', (n * 480, 270))
for i in range(n):
    s.paste(Image.open('D:/i3-pc/tools/dot%d.png' % i).resize((480, 270)), (i * 480, 0))
s.save(sys.argv[1])
PY
echo done
