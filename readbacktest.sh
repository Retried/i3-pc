#!/bin/bash
# Shooting soak with the emulator's on-demand readback switched on in the test profile
# (GPU.readbacks_mode), once per given mode; prints alive or died, dropped draws, frame rate.
# The profile's own value is put back at the end.   ./readbacktest.sh [modes, default "1 2"]
cd /d/i3-pc || exit 1
C=testrun/user/config.json; L=testrun/user/log/shad_log.txt
cp $C tools/config.readbacktest.bak
setmode() { tools/venv/Scripts/python - "$1" <<'PY'
import json, sys
p = 'D:/i3-pc/testrun/user/config.json'
c = json.load(open(p, encoding='utf-8'))
c['GPU']['readbacks_mode'] = int(sys.argv[1])
json.dump(c, open(p, 'w', encoding='utf-8'), indent=4)
PY
}
for m in ${@:-1 2}; do
    [ -f HOLD ] && { echo "HOLD set, stopping"; break; }
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy, stopping"; break; }
    rm -f SLOT_DONE; setmode $m; v=readback$m
    BIN=${BIN:-/d/i3-pc/bin-release} ./shootsoak.sh $v 2>&1 | grep -E "^$v:|Unhandled" | cut -c1-150
    cp $L tools/readbacktest_$v.log
    echo "$v: dropped $(grep -a -c 'Dropped indirect' $L), $(tail -1 livestart.log)"
    grep -a "Flip: fps" $L | sed 's/.*fps \([0-9.]*\).*/\1/' | awk -v l=$v '{s+=$1; n++} END {if (n) printf "%s: mean flip rate %.1f over %d samples\n", l, s/n, n}'
    taskkill //IM i3.exe //F > /dev/null 2>&1; touch SLOT_DONE; sleep 4
done 2>&1 | tee tools/readbacktest_result.txt
cp tools/config.readbacktest.bak $C
date +%H:%M:%S
