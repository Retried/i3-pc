#!/bin/bash
# Frame-time capture while moving, unpaused: ./ft.sh <label> <fixture> [VAR=value ...]
# Routes: fishcannery = run along the road to the cannery gate; insidecannery = doorway dash,
# cutscene, timber hits, burned room. Writes tools/ft_<label>.txt (ms per frame) and the log.
cd /d/i3-pc || exit 1
label=$1; fx=$2; shift; shift
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/$fx-CUSA00004 $S/CUSA00004
rm -f testrun/bench_frametimes.txt
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 400 "45:cross,60:cross" "$@" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
F=testrun/live_cmds.txt
k() { echo "$1" >> $F; sleep "$2"; }
k bench=on 0.2
case $fx in
fishcannery)
    k "key=w*2000" 2.1; k "mouse=30*800" 1; for i in 1 2 3; do k "key=w*2500" 2.6; done
    k "mouse=30*700" 1; for i in 1 2 3; do k "key=w*3000" 3.1; done; k "mouse=30*500" 0.8
    for i in 1 2 3 4; do k "key=w*3000" 3.1; done; k "mouse=-30*2600" 2.8
    for i in 1 2 3 4 5 6; do k "key=w*3000" 3.1; done; k "mouse=30*2600" 2.8
    for i in 1 2 3 4 5 6; do k "key=w*3000" 3.1; done;;
seattle|roadtoseattle)
    # Open ground: run, dash, turn, shoot, jump, for about 90 s.
    for r in 1 2 3 4 5 6; do
        k "key=w*3000" 1.5; k "key=lshift" 1.6; k "key=w*3000" 1.5; k "key=space" 1.6
        k "mouse=30*900" 1.1; k "key=rightbutton*1500" 0.3; k "key=leftbutton" 0.6; k "key=leftbutton" 0.8
        k "key=w*2500" 2.6; k "mouse=-30*500" 0.7; [ -n "$SHOTS" ] && echo shot >> $F
    done;;
*)
    k "key=w*2500" 2.7; echo "key=lshift" >> $F; k "key=w*2500" 2.7; k "key=w*2500" 2.7; sleep 40
    for i in 1 2 3 4 5 6; do k "key=f" 1.0; done; k "key=w*2500" 2.7
    for i in 1 2 3 4 5 6; do k "key=f" 1.0; done; k "key=w*2500" 2.7
    for i in 1 2 3 4 5 6; do k "mouse=30*1300" 1.5; k "key=w*1500" 1.6; k "key=f" 1; done;;
esac
k bench=off 1
cp testrun/bench_frametimes.txt tools/ft_$label.txt; cp testrun/user/log/shad_log.txt tools/ft_$label.log
echo quit >> $F; sleep 8
/d/i3-pc/tools/venv/Scripts/python - "$label" <<'PY'
import sys
import numpy as np
label = sys.argv[1]
t = np.array([float(x) for x in open('D:/i3-pc/tools/ft_%s.txt' % label).read().split() if x.replace('.', '', 1).isdigit()])
at = np.cumsum(t) / 1000
print('%s: frames %d, %.0f s, avg %.1f fps, median %.1f ms, p99 %.1f ms, p99.9 %.1f ms, worst %.0f ms' % (label, len(t), at[-1], 1000 / t.mean(), np.median(t), np.percentile(t, 99), np.percentile(t, 99.9), t.max()))
for lim in (25, 34, 50, 100, 250):
    print('  frames over %d ms: %d' % (lim, (t > lim).sum()))
big = np.flatnonzero(t > 50)
print('  spikes over 50 ms (second: ms):', ' '.join('%.0f:%.0f' % (at[i], t[i]) for i in big[:40]))
log = open('D:/i3-pc/tools/ft_%s.log' % label, encoding='utf-8', errors='replace').read()
for word in ('Compiling graphics pipeline', 'Compiling compute pipeline', 'Compiling', 'Dropped indirect'):
    print('  log "%s": %d' % (word, log.count(word)))
PY
