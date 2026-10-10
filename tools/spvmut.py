"""Mutate a .spv to bisect a driver crash: python spvmut.py in.spv out.spv mut[,mut...]
muts: noatomic (atomics -> plain load), nomembar, noctlbar, noreconv, nofloatctl"""
import struct, sys
d = open(sys.argv[1], 'rb').read(); muts = set(sys.argv[3].split(','))
w = list(struct.unpack('<%dI' % (len(d) // 4), d)); out = w[:5]; i = 5
NOP = 1 << 16
while i < len(w):
    wc, op = w[i] >> 16, w[i] & 0xffff; ins = w[i:i + wc]; a = ins[1:]
    if 'noatomic' in muts and 229 <= op <= 242 and op not in (228,):
        # result type, result id, pointer, ... -> OpLoad
        ins = [(4 << 16) | 61, a[0], a[1], a[2]] + [NOP] * (wc - 4)
    elif 'nomembar' in muts and op == 225: ins = [NOP] * wc
    elif 'noctlbar' in muts and op == 224: ins = [NOP] * wc
    elif 'noreconv' in muts and op == 16 and a[1] == 6023: ins = []
    elif 'nofloatctl' in muts and op == 16 and a[1] in (4459, 4460, 4461, 4462, 4463): ins = []
    out += ins; i += wc
open(sys.argv[2], 'wb').write(struct.pack('<%dI' % len(out), *out))
