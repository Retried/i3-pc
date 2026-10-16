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
    if len(p) in (6, 8):
        # The current sampler appends power/temperature after the original columns.
        samples.append([float(x) if x else 0.0 for x in p[:6]])
samples = np.array(samples) if samples else np.zeros((1, 6))
samples[:, 0] -= rec_start

W, H = 1920, 1080
font_dir = 'C:/Windows/Fonts/'
face = next(f for f in ('pala.ttf', 'georgia.ttf', 'times.ttf') if os.path.exists(font_dir + f))
mid = ImageFont.truetype(font_dir + face, 30)
small = ImageFont.truetype(font_dir + face, 22)
ORANGE, WHITE, GREY, GREEN = (240, 160, 60), (236, 236, 236), (200, 200, 200), (140, 235, 130)

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

# The readout of the Shadow of the Colossus clips: a title line, rows of label and figures, the
# frame-time graph, a line naming the PC. Top right, 1920x1080 picture.
PW, PH = 760, 500
PX, PY = W - PW - 40, 40
GX, GY, GW, GH = PX + 26, PY + 310, PW - 52, 110
C1, C2, C3, C4 = PX + 26, PX + 240, PX + 420, PX + PW - 26
overall = ft[(ft_at >= start_s) & (ft_at <= start_s + (last - first) / rate)]
# Windows' GPU load counters stay near zero for this program on some drivers: the figure is
# shown only when the run measured a believable one.
gpu_known = samples[:, 3].max() >= 5.0

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
        d.rounded_rectangle([PX, PY, PX + PW, PY + PH], radius=12, fill=(24, 24, 24, 205))
        # The last second of frames gives the current figure; average and 1% low count from
        # the first frame of the clip.
        sec = ft[(ft_at > t - 1.0) & (ft_at <= t)]
        run_ft = ft[(ft_at >= start_s) & (ft_at <= t)]
        fps = 1000.0 / sec.mean() if len(sec) else 0.0
        avg = 1000.0 / run_ft.mean() if len(run_ft) else 0.0
        low = 1000.0 / np.percentile(run_ft, 99) if len(run_ft) else 0.0
        i = int(np.argmin(np.abs(samples[:, 0] - t)))
        _, cpu, thread, gpu, vram, ram = samples[i]
        d.text((C1, PY + 18), '%s - %s' % (scene, settings), font=mid, fill=WHITE)
        rows = [('FPS', '%.0f' % fps, 'avg %.0f' % avg, '1%% low %.0f' % low),
                ('GPU', '%.0f %%' % min(gpu, 100.0) if gpu_known else 'not read',
                 '%.1f GB' % (vram / 1024.0), ''),
                ('CPU', '%.0f %%' % cpu, 'busiest thread %.0f %%' % min(thread, 100.0), ''),
                ('RAM', '%.1f GB' % (ram / 1024.0), '', ''),
                ('Frametime', '%.1f ms' % (sec[-1] if len(sec) else 0.0), '', '1920 x 1080')]
        for r, (name, value, second, right) in enumerate(rows):
            y = PY + 70 + 46 * r
            d.text((C1, y), name, font=mid, fill=ORANGE)
            d.text((C2, y), value, font=mid, fill=WHITE)
            d.text((C3, y), second, font=mid, fill=GREY)
            d.text((C4 - d.textlength(right, font=mid), y), right, font=mid, fill=GREY)
        d.rectangle([GX, GY, GX + GW, GY + GH], fill=(0, 0, 0, 170))
        for ms in (16.7, 33.3):
            y = GY + GH - ms / 50.0 * GH
            d.line([GX, y, GX + GW, y], fill=(90, 90, 90, 255))
        sel = (ft_at > t - 10.0) & (ft_at <= t)
        if sel.sum() > 1:
            xs = GX + (ft_at[sel] - (t - 10.0)) / 10.0 * GW
            ys = GY + GH - np.minimum(ft[sel], 50.0) / 50.0 * GH
            d.line(list(zip(xs.tolist(), ys.tolist())), fill=GREEN + (255,), width=2)
        note = 'Ryzen 7 5700X3D, Radeon RX 9060 XT - figures measured while recording'
        d.text((C1, PY + PH - 68), note, font=small, fill=GREY)
        if uncaptured:
            d.text((C1, PY + PH - 40), 'Without recording, just before the clip: %s' % uncaptured, font=small, fill=GREY)
        img = Image.alpha_composite(img.convert('RGBA'), panel).convert('RGB')
        enc.stdin.write(img.tobytes())
enc.stdin.close()
enc.wait()
print('samples %d, GPU load max %.0f %%, video memory max %.0f MB' % (
    len(samples), samples[:, 3].max(), samples[:, 4].max()))
if len(overall):
    print('%s, %s: recorded avg %.1f fps, 1%% low %.1f, worst frame %.0f ms, frames over 50 ms %d, '
          'over 100 ms %d, of %d' % (
              scene, settings, 1000.0 / overall.mean(), 1000.0 / np.percentile(overall, 99),
              overall.max(), int((overall > 50).sum()), int((overall > 100).sum()), len(overall)))
