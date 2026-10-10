#!/bin/bash
# Spray-stencil aim test: ./spraytest.sh out.png [VAR=value ...] -> 4-up sheet (centre, left, up, right-down)
cd /d/i3-pc || exit 1
out=$1; shift
./livestart.sh 150 "45:cross,60:cross,75:cross,95:cross" "$@" > /dev/null
sleep 20; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 80
./live.sh "key=g*250000" wait=5 > /dev/null; ./live.sh "key=h*4000" wait=10 > /dev/null
./live.sh "key=leftbutton*30000" wait=1.5 > /dev/null; cp tools/live.png tools/s0.png
./live.sh "key=a*600" wait=1.2 > /dev/null; cp tools/live.png tools/s1.png
./live.sh "key=w*600" wait=1.2 > /dev/null; cp tools/live.png tools/s2.png
./live.sh "key=d*1200" "key=s*1200" wait=2 > /dev/null; cp tools/live.png tools/s3.png
echo quit >> testrun/live_cmds.txt
tools/venv/Scripts/python - "$out" <<'PY'
import sys
from PIL import Image
s = Image.new('RGB', (1920, 1080))
for i in range(4):
    s.paste(Image.open('D:/i3-pc/tools/s%d.png' % i), ((i % 2) * 960, (i // 2) * 540))
s.resize((1280, 720)).save(sys.argv[1])
PY
until [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; do sleep 2; done; echo done
