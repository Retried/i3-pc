"""Summarise testrun/profile_full.txt by function: python symprof.py [top]"""
import collections, subprocess, sys, glob, shutil, os
top = int(sys.argv[1]) if len(sys.argv) > 1 else 40
rows = [l.split() for l in open('D:/i3-pc/testrun/profile_full.txt').read().splitlines()[1:]]
addrs = sorted({a for r in rows for a in r[1:] if a != '0'})
# llvm-symbolizer wants the image under its original name next to the PDB.
exe = 'D:/i3-pc/bin/shadps4.exe'
shutil.copyfile('D:/i3-pc/bin/i3.exe', exe)
tool = glob.glob('D:/sotc-pc/toolchain/*/bin/llvm-symbolizer.exe')[0]
out = subprocess.run([tool, '--obj=' + exe, '-f', '-C', '-s', '--no-inlines'], input='\n'.join('0x' + a for a in addrs),
                     capture_output=True, text=True).stdout.split('\n\n')
os.remove(exe)
name = {a: (o.strip().split('\n')[0][:90] if o.strip() else '?') for a, o in zip(addrs, out)}
leaf = collections.Counter(); incl = collections.Counter(); total = 0
for r in rows:
    c = int(r[0]); total += c
    fr = [name.get(a, 'outside') for a in r[1:] if a != '0']
    leaf[fr[0] if fr else 'none'] += c
    for f in set(fr): incl[f] += c
print('samples', total)
print('--- innermost frame of ours'); [print('%5.1f%% %s' % (100 * c / total, f)) for f, c in leaf.most_common(top)]
print('--- any of the three innermost frames'); [print('%5.1f%% %s' % (100 * c / total, f)) for f, c in incl.most_common(top)]
