"""Who calls a hot function: python symcallers.py <profile file> <name part> [<name part> ...]
For every sample whose innermost frame matches a name part, counts the next frame up."""
import collections, subprocess, sys, glob, shutil, os
path, parts = sys.argv[1], sys.argv[2:]
rows = [l.split() for l in open(path).read().splitlines()[1:]]
addrs = sorted({a for r in rows for a in r[1:] if a != '0'})
exe = 'D:/i3-pc/bin/shadps4.exe'
shutil.copyfile('D:/i3-pc/bin/i3.exe', exe)
tool = glob.glob('D:/sotc-pc/toolchain/*/bin/llvm-symbolizer.exe')[0]
out = subprocess.run([tool, '--obj=' + exe, '-f', '-C', '-s', '--no-inlines'], input='\n'.join('0x' + a for a in addrs),
                     capture_output=True, text=True).stdout.split('\n\n')
os.remove(exe)
name = {a: (' @ '.join(o.strip().split('\n')[:2])[:110] if o.strip() else '?') for a, o in zip(addrs, out)}
total = sum(int(r[0]) for r in rows)
for part in parts:
    callers = collections.Counter(); hits = 0
    for r in rows:
        fr = [name.get(a, 'outside') for a in r[1:] if a != '0']
        if fr and part in fr[0]:
            hits += int(r[0])
            callers[fr[1] if len(fr) > 1 else 'none'] += int(r[0])
    print('%s: %.1f%% of samples' % (part, 100.0 * hits / total))
    for f, c in callers.most_common(6):
        print('   %5.1f%%  %s' % (100.0 * c / total, f))
