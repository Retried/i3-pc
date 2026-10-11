#!/bin/bash
# Hank fight, unpaused, 40 s recorded: ./zz.sh <label> [skipfs hashes ...]
# Reports frames with a white-hot core next to orange flame and saves the two strongest.
cd /d/i3-pc || exit 1
label=$1; shift
until [ "$(tasklist | grep -ci -E 'ffmpeg|ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] && [ ! -f HOLD ]; do sleep 15; done
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/defeathank-CUSA00004 $S/CUSA00004
rm -rf testrun/user/capture
BIN=${BIN:-/d/i3-pc/bin} ./livestart.sh 400 "45:cross,60:cross" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done
until grep -q "Flip: fps [3-9][0-9]" testrun/user/log/shad_log.txt 2>/dev/null; do sleep 5; done; sleep 30
F=testrun/live_cmds.txt
k() { echo "$1" >> $F; sleep "$2"; }
for i in 1 2 3 4 5 6 7 8 9; do k "mouse=30*1100" 1.2; done
for h in "$@"; do k "skipfs=$h" 0.2; done
k rec=on 0.2
for i in 1 2 3 4 5 6 7 8; do k "key=a*1200" 1.3; k "key=d*1200" 1.3; k "mouse=30*300" 0.4; k "mouse=-30*300" 2; done
k rec=off 1; echo quit >> $F; sleep 8
/d/i3-pc/tools/venv/Scripts/python - "$label" <<'PY'
import os, sys
import numpy as np
from PIL import Image
label = sys.argv[1]
p = 'D:/i3-pc/testrun/user/capture/frames.rgb'
n = os.path.getsize(p) // (960 * 540 * 3)
a = np.memmap(p, dtype=np.uint8, shape=(n, 540, 960, 3))
score = []
for i in range(n):
    f = a[i].astype(np.int16)
    white = (f[..., 0] > 235) & (f[..., 1] > 215) & (f[..., 2] > 170)
    orange = (f[..., 0] > 210) & (f[..., 1] > 90) & (f[..., 1] < 190) & (f[..., 2] < 90)
    near = np.zeros_like(orange); near[:, 4:] |= orange[:, :-4]; near[:, :-4] |= orange[:, 4:]; near[4:] |= orange[:-4]; near[:-4] |= orange[4:]
    score.append((int((white & near).sum()), int(orange.sum())))
s = np.array(score)
print('%s: frames %d, with flame %d, with white core beside flame (>20 px) %d, max core %d px' % (label, n, int((s[:, 1] > 60).sum()), int((s[:, 0] > 20).sum()), int(s[:, 0].max())))
for rank, i in enumerate(np.argsort(-s[:, 0])[:2]):
    Image.fromarray(np.asarray(a[i])).save('D:/i3-pc/tools/zz_%s_%d.png' % (label, rank))
PY
