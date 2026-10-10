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
for layer in 1 2 3 4 5; do
    for p in 0.06 0.01 -0.04 -0.09 -0.14 -0.19 -0.24 -0.29; do
        echo "key=h*1000" >> $F; sleep 1.2
        echo "aim=${ys%% *},$p" >> $F; sleep 0.2; echo "key=leftbutton*2900" >> $F
        for y in $ys; do echo "aim=$y,$p" >> $F; sleep 0.1; done
        sleep 0.4; [ "$ys" = "$yl" ] && ys=$yr || ys=$yl
    done
    ./live.sh wait=6 > /dev/null; cp tools/live.png tools/layer$layer.png
    [ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && break
done
tools/venv/Scripts/python - <<'PY'
import os
from PIL import Image
s = Image.new('RGB', (5 * 384, 216))
for i in range(5):
    f = 'D:/i3-pc/tools/layer%d.png' % (i + 1)
    if os.path.exists(f): s.paste(Image.open(f).resize((384, 216)), (i * 384, 0))
s.save('D:/i3-pc/tools/layers.png')
PY
