"""Story-progress edit of a test save (never the user's saves): marks the given missions and
all their objectives complete, makes one mission the active one and sets the world name.

Save layout (dis.dat, 128 KiB): at 0x3c5 two u16 (name count, record count), at 0x3cb the
records, 12 bytes each: u16 state (0 idle, 1 active, 3 done), u16 name index, u16 parent
mission's name index (0xffff for none), u16 flag, f32 time. The names follow as
zero-terminated strings. Behind them: the current mission and, further on, the world name.

usage: saveedit.py <src save dir> <dst save dir> <active mission> <world> <done mission>...
"""
import os
import shutil
import struct
import sys

REC = 0x3cb


def edit(path, active, world, done):
    b = bytearray(open(path, 'rb').read())
    n_names, n_recs = struct.unpack_from('<HH', b, 0x3c5)
    o = REC + 12 * n_recs + 4
    names = []
    for _ in range(n_names):
        e = b.index(b'\0', o)
        names.append(b[o:e].decode('latin1'))
        o = e + 1
    idx = {n: i for i, n in enumerate(names)}
    done_ids = {idx[m] for m in done}
    act = idx[active]
    first_child = None
    for r in range(n_recs):
        at = REC + 12 * r
        state, name, parent, flag, t = struct.unpack_from('<HHHHf', b, at)
        if name in done_ids or parent in done_ids:
            struct.pack_into('<HHHH', b, at, 3, name, parent, 1 if parent != 0xffff else flag)
        elif name == act:
            struct.pack_into('<HHHH', b, at, 1, name, parent, 1)
        elif parent == act and names[name].startswith('objective') and first_child is None:
            first_child = name
            struct.pack_into('<HHHH', b, at, 1, name, parent, 1)
    # Current mission: magic, u32 length, string.
    assert b[o:o + 4] == bytes.fromhex('13addbba'), b[o:o + 4].hex()
    ln = struct.unpack_from('<I', b, o + 4)[0]
    cur = active.encode() + b'\0'
    assert len(cur) == ln, 'mission name of another length would move the data behind it'
    b[o + 8:o + 8 + ln] = cur
    w = b.index(b'world_', o)
    old = b[w:b.index(b'\0', w)]
    assert len(old) == len(world), (old, world)
    b[w:w + len(old)] = world.encode()
    open(path, 'wb').write(b)
    return names[first_child] if first_child is not None else None


src, dst, active, world = sys.argv[1:5]
done = sys.argv[5:]
if os.path.exists(dst):
    shutil.rmtree(dst)
shutil.copytree(src, dst)
for slot in os.listdir(dst):
    p = os.path.join(dst, slot, 'dis.dat')
    if os.path.exists(p):
        print(slot, 'first objective:', edit(p, active, world, done))
