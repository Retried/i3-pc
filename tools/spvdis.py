"""Minimal SPIR-V disassembler: python spvdis.py file.spv > out.txt"""
import json, struct, sys
G = json.load(open('D:/sotc-pc/runtime/externals/sirit/externals/SPIRV-Headers/include/spirv/unified1/spirv.core.grammar.json'))
ops = {i['opcode']: i for i in G['instructions']}
kinds = {k['kind']: k for k in G['operand_kinds']}
d = open(sys.argv[1], 'rb').read()
w = struct.unpack('<%dI' % (len(d) // 4), d)
print('; version %x bound %d' % (w[1], w[3]))
i = 5
def enum(kind, v):
    k = kinds.get(kind)
    if not k or 'enumerants' not in k: return None
    if k['category'] == 'BitEnum':
        n = [e['enumerant'] for e in k['enumerants'] if isinstance(e['value'], str) and int(e['value'], 16) & v] 
        return '|'.join(n) or 'None'
    for e in k['enumerants']:
        if e['value'] == v: return e['enumerant']
    return str(v)
while i < len(w):
    wc, op = w[i] >> 16, w[i] & 0xffff
    if wc == 0: print('BAD wordcount at', i); break
    ins = ops.get(op); a = list(w[i + 1:i + wc]); out = []; res = ''
    if ins is None:
        print('Op?%d %s' % (op, a)); i += wc; continue
    j = 0
    for o in ins.get('operands', []):
        if j >= len(a): break
        k = o['kind']; q = o.get('quantifier', '')
        def one():
            global j
            v = a[j]; j += 1
            if k == 'IdResult': return None, '%%%d' % v
            if k.startswith('Id') or k in ('PairIdRefIdRef',): return '%%%d' % v, None
            if k == 'LiteralString':
                bs = struct.pack('<I', v)
                while 0 not in bs: bs += struct.pack('<I', a[j]); j += 1
                return '"%s"' % bs.split(b'\0')[0].decode(), None
            e = enum(k, v)
            return (e if e is not None else str(v)), None
        while j < len(a):
            t, r = one()
            if r: res = r + ' = '
            else: out.append(t)
            if q != '*': break
    out += [str(x) for x in a[j:]]
    print('%s%s %s' % (res, ins['opname'], ' '.join(out)))
    i += wc
