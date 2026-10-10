#!/bin/bash
# Scripted test of the in-game PC options: open, rebind Jump to X, change graphics options.
cd /d/i3-pc || exit 1
./livestart.sh 200 "300:cross" > /dev/null; sleep 25; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 72
F=testrun/live_cmds.txt
g() { sleep "${2:-1.2}"; echo shotui >> $F; sleep 1.6; f=$(ls -t testrun/user/screenshots/*.png | head -1); cp "$f" tools/menu_$1.png; }
k() { echo "key=$1" >> $F; sleep 0.7; }
k f2; g 1 1.5
k enter; g 2 1
k down; k down; k down; k down; k enter; g 3 1; k x; g 4 3
grep -n "^cross" testrun/user/input_config/CUSA00004.ini
k escape; k down; k enter; g 5 1
k d; k down; k down; k down; k down; k d; k down; k d; k down; k d; g 6 1
k escape; g 7 1; k f2; g 8 1
grep -n "vblank_frequency\|fsr_enabled\|rcas" testrun/user/config.json; echo quit >> $F
tools/venv/Scripts/python - <<'PY'
from PIL import Image
s = Image.new('RGB', (4 * 480, 2 * 270))
for i in range(8):
    s.paste(Image.open('D:/i3-pc/tools/menu_%d.png' % (i + 1)).convert('RGB').resize((480, 270)), ((i % 4) * 480, (i // 4) * 270))
s.save('D:/i3-pc/tools/pair.png')
PY
