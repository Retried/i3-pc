"""Contact sheets of dumped BC1/BC3 textures: python texsheet.py <format substring> <out prefix>"""
import glob, io, os, struct, sys
from PIL import Image
fmt_sub, out = sys.argv[1], sys.argv[2]
def dds(w, h, fourcc, data):
    hdr = struct.pack('<4sII II II I 44x II4sIIIII IIII I', b'DDS ', 124, 0x1007 | 0x80000, h, w, len(data), 0, 1,
                      32, 4, fourcc, 0, 0, 0, 0, 0, 0x1000, 0, 0, 0, 0)
    return hdr + data
files = sorted(glob.glob('D:/i3-pc/dist/user/sotc_textures/dump/*%s*.raw' % fmt_sub))
tiles = []
for f in files:
    name = os.path.basename(f); parts = name.split('_'); w, h = map(int, parts[1].split('x'))
    if w > 1024 or h > 1024 or w < 32: continue
    fourcc = b'DXT1' if 'Bc1' in name else b'ATI1' if 'Bc4' in name else b'DXT5'
    try:
        im = Image.open(io.BytesIO(dds(w, h, fourcc, open(f, 'rb').read())))
        if fourcc == b'ATI1':
            g = im.convert('L'); im = Image.merge('RGBA', (g, g, g, Image.new('L', g.size, 255)))
        im = im.convert('RGBA')
    except Exception as e:
        continue
    bg = Image.new('RGBA', im.size, (60, 60, 90, 255)); bg.alpha_composite(im)
    t = bg.convert('RGB'); t.thumbnail((128, 128))
    tiles.append((parts[0][:16], t))
print(len(tiles), 'textures')
per = 12 * 7
for page in range(0, len(tiles), per):
    sheet = Image.new('RGB', (12 * 132, 7 * 132), (20, 20, 20))
    for i, (h, t) in enumerate(tiles[page:page + per]):
        sheet.paste(t, ((i % 12) * 132, (i // 12) * 132))
    sheet.save('%s_%d.png' % (out, page // per))
open(out + '_index.txt', 'w').write('\n'.join(h for h, _ in tiles))
