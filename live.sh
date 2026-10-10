#!/bin/bash
# Live steering: ./live.sh "<action>" ... wait=<s> sends actions to the running game, waits,
# takes a screenshot and writes a 960x540 copy to tools/live.png. Example: ./live.sh "key=w*3000" wait=4
F=/d/i3-pc/testrun/live_cmds.txt
w=1
for a in "$@"; do
    case "$a" in wait=*) w=${a#wait=};; *) echo "$a" >> "$F";; esac
done
sleep "$w"
echo ${SHOT:-shot} >> "$F"
sleep 1.5
/d/i3-pc/tools/venv/Scripts/python - <<'PY'
import glob, os
from PIL import Image
f = max(glob.glob('D:/i3-pc/testrun/user/screenshots/*.png'), key=os.path.getmtime)
Image.open(f).convert('RGB').resize((960, 540)).save('D:/i3-pc/tools/live.png')
PY
grep "Flip: fps" /d/i3-pc/testrun/user/log/shad_log.txt | tail -1 | sed -E 's/^.*fps /fps /'
