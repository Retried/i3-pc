#!/bin/bash
# Play on from the Seattle fixture: run forward along the bridge with jumps and dashes for about
# three minutes, a screenshot every 15 seconds (tools/sp_N.png), frame times logged for the
# whole stretch. Optimized build. Direct launch: only in an agreed slot.
#   ./seattleplay.sh [fixture, default seattle]
cd /d/i3-pc || exit 1
fx=${1:-seattle}
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/$fx-CUSA00004 $S/CUSA00004
rm -f testrun/user/screenshots/*.png testrun/bench_frametimes.txt tools/sp_*.png
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 420 "45:cross,60:cross" > /dev/null; sleep 100
F=testrun/live_cmds.txt
k() { echo "$1" >> $F; sleep "$2"; }
echo "bench=on" >> $F
for r in 1 2 3 4 5 6 7 8 9 10 11 12; do
    k "shot" 1
    k "key=w*6000" 2; k "key=space" 1; k "key=space" 1; k "key=lshift" 2
    k "key=w*6000" 2; k "key=space" 1; k "key=lshift" 2; k "key=leftbutton" 2
done
k "shot" 1
printf "bench=off\n" >> $F; sleep 2
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
n=0; for f in $(ls -tr testrun/user/screenshots/*.png); do n=$((n + 1)); cp "$f" tools/sp_$n.png; done
echo "screenshots: $n"
tools/venv/Scripts/python - <<'EOF'
import numpy as np
ft = np.array([float(x) for x in open('D:/i3-pc/testrun/bench_frametimes.txt').read().split()])
print('frames %d, %.0f s, avg %.1f fps, p99 %.1f ms, worst %.0f ms, over 100 ms: %d' % (
    len(ft), ft.sum() / 1000, 1000 / ft.mean(), np.percentile(ft, 99), ft.max(), (ft > 100).sum()))
EOF
grep -a "Unhandled\|Assert" testrun/user/log/shad_log.txt | tail -2 | cut -c1-200
