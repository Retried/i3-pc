#!/bin/bash
# Cannery scene check from the save: ./bright.sh [VAR=value ...] -> mean brightness (good = 59) and FPS.
cd /d/i3-pc || exit 1
until [ "$(tasklist | grep -ci '^i3.exe')" = "0" ]; do sleep 2; done
rm -f testrun/user/screenshots/*.png
./test.sh 118 SOTC_SCRIPT="45:cross,60:cross,112:shot" "$@" 2>&1 | grep -v Killed | tail -2
tools/venv/Scripts/python - <<'PY'
import glob, os
from PIL import Image, ImageStat
fs = glob.glob('D:/i3-pc/testrun/user/screenshots/*.png')
if fs:
    f = max(fs, key=os.path.getmtime)
    Image.open(f).convert('RGB').resize((960, 540)).save('D:/i3-pc/tools/live.png')
    print('brightness %.1f' % ImageStat.Stat(Image.open(f).convert('L')).mean[0])
else:
    print('no screenshot')
PY
grep "Flip: fps" testrun/user/log/shad_log.txt | awk '{print $7}' | tail -4 | tr '\n' ' '; echo
