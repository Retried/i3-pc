#!/bin/bash
# Paused stepping for timed sections: ./stepper.sh <run seconds> "<action>" ... -> tools/live.png
# The game is resumed, the actions are sent, it runs for the given time, is paused again and a
# screenshot is taken. Start the session with livestart.sh and one "./stepper.sh 0" to pause.
F=/d/i3-pc/testrun/live_cmds.txt
t=$1; shift
echo resume >> $F
for a in "$@"; do echo "$a" >> $F; done
sleep "$t"
echo pause >> $F; sleep 0.6; echo shotui >> $F; sleep 1.6
/d/i3-pc/tools/venv/Scripts/python - <<'PY'
import glob, os
from PIL import Image
f = max(glob.glob('D:/i3-pc/testrun/user/screenshots/*.png'), key=os.path.getmtime)
Image.open(f).convert('RGB').resize((960, 540)).save('D:/i3-pc/tools/live.png')
PY
