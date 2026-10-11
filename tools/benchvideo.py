"""Benchmark clip with a performance panel drawn into the picture.

Inputs, all written by one test run (benchclip.sh):
  capture/frames.rgb, frames.txt  the runtime's own capture: half-size RGB frames, 30 a second
  capture/audio.f32               the game's stereo float output, 48 kHz
  bench_frametimes.txt            milliseconds between presented frames, started with the capture
  perf_samples.csv                tools/perfsample.ps1, one line a second
The panel shows what was measured during this capture; the capture itself costs frame rate, so
the frame rate of the same scene without capture is printed under it when given.

usage: benchvideo.py <run dir> <out.mp4> <scene> <settings> [uncaptured fps text] [start s] [length s]
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

run, out, scene, settings = sys.argv[1:5]
uncaptured = sys.argv[5] if len(sys.argv) > 5 else ''
start_s = float(sys.argv[6]) if len(sys.argv) > 6 else 0.0
length_s = float(sys.argv[7]) if len(sys.argv) > 7 else 1e9

cap = os.path.join(run, 'user', 'capture')
w, h, rate = (int(x) for x in open(os.path.join(cap, 'frames.txt')).read().split())
frame_bytes = w * h * 3
n_frames = os.path.getsize(os.path.join(cap, 'frames.rgb')) // frame_bytes
rec_start = os.path.getctime(os.path.join(cap, 'frames.txt'))

ft = np.array([float(x) for x in open(os.path.join(run, 'bench_frametimes.txt')).read().split()])
ft_at = np.cumsum(ft) / 1000.0  # seconds since the capture began, at the end of each frame

samples = []
for line in open(os.path.join(run, 'perf_samples.csv')).read().split('\n')[1:]:
    p = line.split(',')
    if len(p) == 6:
        samples.append([float(x) if x else 0.0 for x in p])
samples = np.array(samples) if samples else np.zeros((1, 6))
samples[:, 0] -= rec_start

W, H = 1920, 1080
font_dir = 'C:/Windows/Fonts/'
big = ImageFont.truetype(font_dir + 'bahnschrift.ttf', 54)
mid = ImageFont.truetype(font_dir + 'bahnschrift.ttf', 26)
small = ImageFont.truetype(font_dir + 'bahnschrift.ttf', 20)
YELLOW, WHITE, GREY = (246, 190, 0), (236, 236, 236), (160, 160, 160)

first = int(start_s * rate)
last = min(n_frames, first + int(length_s * rate))
audio = os.path.join(cap, 'audio.f32')
cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s',
       '%dx%d' % (W, H), '-r', str(rate), '-i', '-']
if os.path.exists(audio):
    cmd += ['-f', 'f32le', '-ar', '48000', '-ac', '2', '-ss', '%.3f' % start_s, '-i', audio]
cmd += ['-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
        '-b:a', '160k', '-shortest', out]
enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)

PX, PY, PW, PH = 28, 28, 470, 372
GX, GY, GW, GH = PX + 18, PY + 236, PW - 36, 84
overall = ft[(ft_at >= start_s) & (ft_at <= start_s + (last - first) / rate)]

with open(os.path.join(cap, 'frames.rgb'), 'rb') as f:
    f.seek(first * frame_bytes)
    for k in range(first, last):
        raw = f.read(frame_bytes)
        if len(raw) < frame_bytes:
            break
        t = k / rate
        img = Image.frombytes('RGB', (w, h), raw).resize((W, H), Image.BILINEAR)
        panel = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(panel)
        d.rectangle([PX, PY, PX + PW, PY + PH], fill=(12, 12, 12, 205), outline=(236, 236, 236, 255), width=2)
        # The last second of frames gives the current figure; the last five the lows.
        sec = ft[(ft_at > t - 1.0) & (ft_at <= t)]
        win = ft[(ft_at > t - 5.0) & (ft_at <= t)]
        fps = 1000.0 / sec.mean() if len(sec) else 0.0
        avg = 1000.0 / win.mean() if len(win) else 0.0
        low = 1000.0 / np.percentile(win, 99) if len(win) else 0.0
        d.text((PX + 18, PY + 10), '%.0f' % fps, font=big, fill=YELLOW)
        d.text((PX + 110, PY + 34), 'FPS', font=mid, fill=WHITE)
        d.text((PX + 190, PY + 16), 'avg %.1f   1%% low %.1f' % (avg, low), font=small, fill=WHITE)
        d.text((PX + 190, PY + 42), 'frame %.1f ms' % (sec[-1] if len(sec) else 0.0), font=small, fill=WHITE)
        i = int(np.argmin(np.abs(samples[:, 0] - t)))
        _, cpu, thread, gpu, vram, ram = samples[i]
        rows = [('CPU', '%.0f %%   busiest thread %.0f %%' % (cpu, min(thread, 100.0))),
                # Windows' GPU load counters stay near zero for this program on some drivers:
                # the figure is shown only when the run measured a believable one.
                ('GPU', ('%.0f %%   ' % min(gpu, 100.0) if samples[:, 3].max() >= 5.0 else '') +
                 'video memory %.1f GB' % (vram / 1024.0)),
                ('RAM', '%.1f GB' % (ram / 1024.0)),
                ('', '1920x1080   %s' % settings)]
        for r, (name, text) in enumerate(rows):
            y = PY + 84 + 30 * r
            d.text((PX + 18, y), name, font=small, fill=GREY)
            d.text((PX + 78 if name else PX + 18, y), text, font=small, fill=WHITE)
        d.text((PX + 18, PY + 206), 'FRAME TIME, LAST 10 S (0-50 ms)', font=small, fill=GREY)
        d.rectangle([GX, GY, GX + GW, GY + GH], fill=(0, 0, 0, 160))
        for ms in (16.7, 33.3):
            y = GY + GH - ms / 50.0 * GH
            d.line([GX, y, GX + GW, y], fill=(120, 120, 120, 255))
        sel = (ft_at > t - 10.0) & (ft_at <= t)
        if sel.sum() > 1:
            xs = GX + (ft_at[sel] - (t - 10.0)) / 10.0 * GW
            ys = GY + GH - np.minimum(ft[sel], 50.0) / 50.0 * GH
            d.line(list(zip(xs.tolist(), ys.tolist())), fill=YELLOW + (255,), width=2)
        d.text((PX + 18, PY + PH - 46), scene, font=mid, fill=WHITE)
        note = 'Measured while capturing.'
        if uncaptured:
            note += ' Without capture: %s' % uncaptured
        d.text((PX, PY + PH + 8), note, font=small, fill=WHITE, stroke_width=2, stroke_fill=(0, 0, 0))
        img = Image.alpha_composite(img.convert('RGBA'), panel).convert('RGB')
        enc.stdin.write(img.tobytes())
enc.stdin.close()
enc.wait()
print('samples %d, GPU load max %.0f %%, video memory max %.0f MB' % (
    len(samples), samples[:, 3].max(), samples[:, 4].max()))
if len(overall):
    print('%s: captured avg %.1f fps, 1%% low %.1f, worst %.0f ms, frames %d' % (
        scene, 1000.0 / overall.mean(), 1000.0 / np.percentile(overall, 99), overall.max(), len(overall)))
