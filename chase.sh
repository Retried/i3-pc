#!/bin/bash
# Chase attempt: loop "locate objective (V), run forward with dash taps". Screenshots every few steps.
cd /d/i3-pc || exit 1
until [ "$(tasklist | grep -ciE 'shadps4|sotc_ab|ShadowOfTheColossus|inFAMOUS Second|^i3.exe')" = "0" ]; do sleep 3; done
./livestart.sh 330 "300:cross" > /dev/null; sleep 25; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 70
F=testrun/live_cmds.txt; n=0
for i in $(seq 1 ${STEPS:-45}); do
    [ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && break
    echo "key=v" >> $F; sleep 0.9
    echo "key=w*2200" >> $F; sleep 0.7; echo "key=lshift" >> $F; sleep 0.8; echo "key=lshift" >> $F; sleep 0.9
    if [ $((i % 5)) = 0 ]; then echo shot >> $F; sleep 1.5; f=$(ls -t testrun/user/screenshots/*.png | head -1); n=$((n+1)); cp "$f" tools/chase_$n.png; fi
done
tools/venv/Scripts/python - $n <<'PY'
import sys
from PIL import Image
n = int(sys.argv[1]); s = Image.new('RGB', (3 * 640, ((n + 2) // 3) * 360))
for i in range(n):
    s.paste(Image.open('D:/i3-pc/tools/chase_%d.png' % (i + 1)).convert('RGB').resize((640, 360)), ((i % 3) * 640, (i // 3) * 360))
s.save('D:/i3-pc/tools/chase.png')
PY
