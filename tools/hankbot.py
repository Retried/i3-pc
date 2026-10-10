"""Closed-loop Hank fight: look for the orange prison suit in each paused screenshot, turn
towards it, run in and hit with the chain. python hankbot.py [steps]"""
import glob
import os
import subprocess
import sys
import time

import numpy as np
from PIL import Image

CMDS = 'D:/i3-pc/testrun/live_cmds.txt'
SHOTS = 'D:/i3-pc/testrun/user/screenshots/*.png'
LOG = 'D:/i3-pc/testrun/user/log/shad_log.txt'
steps = int(sys.argv[1]) if len(sys.argv) > 1 else 90


def send(*actions):
    with open(CMDS, 'a') as f:
        for a in actions:
            f.write(a + '\n')


def alive():
    return b'i3.exe' in subprocess.run(['tasklist'], capture_output=True).stdout


def step(run_s, *actions):
    """Resume, send the actions, let the game run, pause, screenshot; returns the picture."""
    before = set(glob.glob(SHOTS))
    send('resume', *actions)
    time.sleep(run_s)
    send('pause')
    time.sleep(0.5)
    send('shotui')
    for _ in range(40):
        time.sleep(0.1)
        new = set(glob.glob(SHOTS)) - before
        if new:
            time.sleep(0.25)
            f = max(new, key=os.path.getmtime)
            try:
                return np.asarray(Image.open(f).convert('RGB').resize((480, 270))).astype(np.int16)
            except OSError:
                time.sleep(0.3)
                return np.asarray(Image.open(f).convert('RGB').resize((480, 270))).astype(np.int16)
    return None


def find_suit(img):
    """Column and size of the orange suit: saturated orange that is not fire-bright."""
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    mask = (r > 135) & (r < 235) & (g > 45) & (g < 120) & (b < 60) & (r - g > 70)
    mask[:60] = False     # ceiling lamps, hint text
    mask[235:] = False    # objective label
    # Keep the densest 40-column window: the suit is compact, lit floors are spread out.
    cols = mask.sum(axis=0)
    win = np.convolve(cols, np.ones(40, dtype=int), 'same')
    centre = int(win.argmax())
    count = int(win[centre])
    return centre, count, int(mask.sum())


turn_dir = 1
lost = 0
for n in range(steps):
    if not alive():
        print('game ended at step', n)
        break
    img = step(0.05)
    if img is None:
        print('no screenshot')
        break
    if img.mean() < 4:           # fade after a death or a cutscene cut
        print(n, 'dark frame, waiting')
        step(2.5)
        continue
    centre, count, total = find_suit(img)
    if count < 25:
        lost += 1
        print(n, 'no target (%d px), turning' % count)
        step(0.9, 'mouse=%d*700' % (30 * turn_dir))
        if lost % 12 == 0:      # a full turn found nothing: move somewhere else
            step(2.2, 'key=w*2000', 'key=lshift')
        continue
    lost = 0
    offset = (centre - 240) / 240.0          # -1 .. 1 across the screen
    turn_dir = 1 if offset >= 0 else -1
    turn_ms = int(abs(offset) * 950)
    acts = []
    if turn_ms > 90:
        acts.append('mouse=%d*%d' % (30 * turn_dir, turn_ms))
    if count > 420:                           # close: hit
        print(n, 'target close (%d px) at %+.2f: melee' % (count, offset))
        step(turn_ms / 1000 + 0.15, *acts) if acts else None
        for _ in range(3):
            step(0.55, 'key=f*120')
    else:                                     # run at him, dash when far
        print(n, 'target (%d px) at %+.2f: approach' % (count, offset))
        if acts:
            step(turn_ms / 1000 + 0.1, *acts)
        run = ['key=w*1300'] + (['key=lshift'] if count < 120 else [])
        step(1.4, *run)
    log = open(LOG, encoding='utf-8', errors='replace').read()
    if 'Unlocking trophy id' in log or 'Achievement unlocked' in log:
        print('trophy call seen')
print('done')
