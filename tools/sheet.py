"""Contact sheet of screenshots: python sheet.py out.png [cols] [dir]"""
import glob, sys
from PIL import Image
out = sys.argv[1]; cols = int(sys.argv[2]) if len(sys.argv) > 2 else 3
d = sys.argv[3] if len(sys.argv) > 3 else 'D:/i3-pc/dist/user/screenshots'
fs = sorted(glob.glob(d + '/*.png')); W, H = 640, 360
rows = (len(fs) + cols - 1) // cols
s = Image.new('RGB', (cols * W, rows * H))
for i, f in enumerate(fs):
    s.paste(Image.open(f).convert('RGB').resize((W, H)), ((i % cols) * W, (i // cols) * H))
s.save(out); print(len(fs), 'shots')
