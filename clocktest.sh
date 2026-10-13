#!/bin/bash
# Frame clock test at the crash site: the game presents once per tick of the frame clock, so at
# 60 Hz a frame that needs 18 ms is shown after 33 ms. Runs ft.sh on fixture chase with the
# clock of the test profile at each given rate and prints average, median, 99th percentile and
# the share of frames over 25 ms. The profile's own value is put back at the end.
#   ./clocktest.sh [rates, default "60 120 1000"]       (1000 = uncapped)
cd /d/i3-pc || exit 1
C=testrun/user/config.json
cp $C tools/config.clocktest.bak
setclock() { tools/venv/Scripts/python - "$1" <<'PY'
import json, sys
p = 'D:/i3-pc/testrun/user/config.json'
c = json.load(open(p, encoding='utf-8'))
c['GPU']['vblank_frequency'] = int(sys.argv[1])
json.dump(c, open(p, 'w', encoding='utf-8'), indent=4)
PY
}
for hz in ${@:-60 120 1000}; do
    [ -f HOLD ] && { echo "HOLD set, stopping"; break; }
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy, stopping"; break; }
    rm -f SLOT_DONE
    setclock $hz
    echo "== frame clock $hz Hz"
    BIN=${BIN:-/d/i3-pc/bin-release} ./ft.sh clock$hz ${FX:-chase} | head -3
    taskkill //IM i3.exe //F > /dev/null 2>&1; touch SLOT_DONE; sleep 4
done 2>&1 | tee tools/clocktest_result.txt
cp tools/config.clocktest.bak $C
date +%H:%M:%S
