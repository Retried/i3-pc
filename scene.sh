#!/bin/bash
# Scene check from the installed save: ./scene.sh name [VAR=value ...] -> tools/<name>.png, FPS, render-thread CPU.
cd /d/i3-pc || exit 1
name=$1; shift
# SotC has priority: a run that had to give way is repeated when the machine is free again.
for attempt in 1 2 3 4 5 6 7 8; do
    until [ "$(tasklist | grep -ciE 'shadps4|ShadowOfTheColossus|inFAMOUS Second|^i3.exe')" = "0" ]; do sleep 3; done
    rm -f testrun/user/screenshots/*.png
    out=$(./test.sh 112 SOTC_SCRIPT="45:cross,60:cross,105:shot" "$@" 2>&1 | grep -v Killed | tail -2)
    echo "$out" | grep -q "YIELDED\|REFUSED" || break
done
echo "$out (attempt $attempt)"
tools/venv/Scripts/python - "$name" <<'PY'
import glob, os, sys
from PIL import Image, ImageStat
fs = glob.glob('D:/i3-pc/testrun/user/screenshots/*.png')
if fs:
    f = max(fs, key=os.path.getmtime)
    Image.open(f).convert('RGB').resize((960, 540)).save('D:/i3-pc/tools/%s.png' % sys.argv[1])
    print('brightness %.1f' % ImageStat.Stat(Image.open(f).convert('L')).mean[0])
else:
    print('no screenshot')
PY
echo "fps: $(grep 'Flip: fps' testrun/user/log/shad_log.txt | awk '{print $7}' | tail -5 | tr '\n' ' ')"
grep "cpu/3s" testrun/user/log/shad_log.txt | tail -2 | cut -c88-150
grep "stats/3s" testrun/user/log/shad_log.txt | tail -1 | cut -c75-200
grep -c "Critical" testrun/user/log/shad_log.txt
