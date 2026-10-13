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
    """Send the actions, let the game run, screenshot; returns the picture."""
    before = set(glob.glob(SHOTS))
    # No pausing: sessions that pause and resume every second have crashed the game.
    send(*actions)
    time.sleep(run_s)
    send('shot')
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
    """Centre column, pixel count and box of the orange suit. The suit is a compact upright
    blob; lit floors and pillars of a similar colour are wide or very large, so the densest
    26x44 window has to hold most of the orange found around it."""
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    mask = (r > 150) & (r < 245) & (g > 50) & (g < 125) & (b < 55) & (r - g > 80) & (g - b > 15)
    mask[:50] = False
    mask[232:] = False
    m = mask.astype(np.int32)
    c = np.cumsum(np.cumsum(m, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)))
    bh, bw = 44, 26
    win = c[bh:, bw:] - c[:-bh, bw:] - c[bh:, :-bw] + c[:-bh, :-bw]
    y, x = np.unravel_index(int(win.argmax()), win.shape)
    count = int(win[y, x])
    # Orange in a wider neighbourhood: a floor or wall keeps going, a person does not.
    y0, y1, x0, x1 = max(0, y - 20), min(270, y + bh + 20), max(0, x - 40), min(480, x + bw + 40)
    around = int(m[y0:y1, x0:x1].sum())
    compact = count >= 0.6 * around
    return x + bw // 2, (count if compact else 0), y + bh // 2


turn_dir = 1
lost = 0
seen = 0
shots = 0
for n in range(steps):
    if not alive():
        print('game ended at step', n)
        break
    img = step(0.05)
    if img is None:
        print('no screenshot')
        break
    if n % 5 == 0:               # a picture every few steps, to look at the run afterwards
        Image.fromarray(img.astype(np.uint8)).resize((320, 180)).save('D:/i3-pc/tools/hbseq_%03d.png' % (n // 5))
    if img.mean() < 4:           # fade after a death or a cutscene cut
        print(n, 'dark frame, waiting')
        step(2.5)
        continue
    centre, count, row = find_suit(img)
    if count < 18:
        lost += 1
        if n % 10 == 0:
            print(n, 'no target, turning')
        step(0.75, 'mouse=%d*600' % (30 * turn_dir))
        if lost % 14 == 0:      # a full turn found nothing: move somewhere else
            step(2.2, 'key=w*2000', 'key=lshift')
        continue
    lost = 0
    seen += 1
    offset = (centre - 240) / 240.0          # -1 .. 1 across the screen
    turn_dir = 1 if offset >= 0 else -1
    if seen <= 12:
        Image.fromarray(img.astype(np.uint8)).save('D:/i3-pc/tools/hb_%02d_x%d_y%d_n%d.png' % (seen, centre, row, count))
    if abs(offset) > 0.10:
        step(abs(offset) * 0.75 + 0.1, 'mouse=%d*%d' % (30 * turn_dir, int(abs(offset) * 750)))
    elif count > 500:
        print(n, 'close (%d px): melee' % count)
        for _ in range(3):
            step(0.5, 'key=f*120')
    else:
        print(n, 'aimed (%d px, row %d): shooting' % (count, row))
        send('key=rightbutton*1400')
        time.sleep(0.35)
        for _ in range(3):
            send('key=leftbutton*90')
            time.sleep(0.33)
        shots += 3
        if shots % 12 == 0:
            step(1.3, 'key=w*1200')          # close the distance a little
    log = open(LOG, encoding='utf-8', errors='replace').read()
    if 'Unlocking trophy id' in log or 'Achievement unlocked' in log:
        print('trophy call seen')
print('done: target seen %d times, %d shots' % (seen, shots))
