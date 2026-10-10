#!/bin/bash
# Tutorial stencil: session that passes the gesture prompts and rasters the spray, shaking before each row.
cd /d/i3-pc || exit 1
until [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; do sleep 3; done
./livestart.sh ${SECS:-330} "45:cross,60:cross,75:cross,95:cross" I3_AIM_RATE=0.35 "$@" > /dev/null
sleep 20; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 80
[ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && { echo "session died"; cat livestart.log | tail -3; exit 1; }
./live.sh "key=g*250000" wait=5 > /dev/null; ./live.sh "key=h*4000" wait=10 > /dev/null
F=testrun/live_cmds.txt; echo "key=w*1300" >> $F; echo "key=a*1500" >> $F; sleep 1.8
dir=d
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    echo "key=h*900" >> $F; sleep 1.2; echo "key=leftbutton*3100" >> $F; echo "key=$dir*2900" >> $F; sleep 3.3
    echo "key=s*260" >> $F; sleep 0.4; [ $dir = d ] && dir=a || dir=d
    ./live.sh wait=0.1 > /dev/null; cp tools/live.png tools/row$i.png
done
./live.sh wait=8 > /dev/null; cp tools/live.png tools/row13.png
tools/venv/Scripts/python - <<'PY'
from PIL import Image
s = Image.new('RGB', (5 * 384, 3 * 216))
for i in range(13):
    s.paste(Image.open('D:/i3-pc/tools/row%d.png' % (i + 1)).resize((384, 216)), ((i % 5) * 384, (i // 5) * 216))
s.save('D:/i3-pc/tools/rows.png')
PY
