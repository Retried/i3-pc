#!/bin/bash
# Tutorial stencil: raster the spray with exact aim angles, shaking before each row.
cd /d/i3-pc || exit 1
until [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; do sleep 3; done
./livestart.sh ${SECS:-330} "45:cross,60:cross,75:cross,95:cross" I3_AIM_MAX=3 "$@" > /dev/null
sleep 20; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 80
[ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && { echo "session died"; tail -3 livestart.log; exit 1; }
./live.sh "key=g*250000" wait=5 > /dev/null; ./live.sh "key=h*4000" wait=10 > /dev/null
F=testrun/live_cmds.txt; n=0
yl="-0.33 -0.30 -0.27 -0.24 -0.21 -0.18 -0.15 -0.12 -0.09 -0.06 -0.03 0 0.03 0.06 0.09 0.12 0.15 0.18 0.21 0.24 0.27 0.30 0.33"
yr=$(echo $yl | tr ' ' '\n' | tac | tr '\n' ' ')
ys=$yl
for p in 0.06 0.02 -0.02 -0.06 -0.10 -0.14 -0.18 -0.22 -0.26 -0.30; do
    echo "key=h*1200" >> $F; sleep 1.5
    echo "aim=${ys%% *},$p" >> $F; sleep 0.2; echo "key=leftbutton*3200" >> $F
    for y in $ys; do echo "aim=$y,$p" >> $F; sleep 0.12; done
    sleep 0.5; [ "$ys" = "$yl" ] && ys=$yr || ys=$yl
    n=$((n+1)); [ $n = 5 ] && { ./live.sh wait=0.1 > /dev/null; cp tools/live.png tools/live_a.png; }
done
./live.sh wait=1 > /dev/null; cp tools/live.png tools/live_b.png; ./live.sh wait=10
tools/venv/Scripts/python - <<'PY'
from PIL import Image
s = Image.new('RGB', (1440, 270))
for i, n in enumerate(['live_a', 'live_b', 'live']):
    s.paste(Image.open('D:/i3-pc/tools/%s.png' % n).resize((480, 270)), (i * 480, 0))
s.save('D:/i3-pc/tools/pair.png')
PY
