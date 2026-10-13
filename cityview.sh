#!/bin/bash
# Frame rate of the slow view in Seattle (camera turned from the bridge to the city) under each
# Shadow Preset. Optimized build. Each run: Seattle save, 13 turn steps to the right (the first
# eleven run at 60 FPS, so the view is the same in every run), 24 seconds measured, a screenshot
# (tools/cityview_<preset>.png). Direct launch: only in an agreed slot. About 3.5 minutes a run.
#   ./cityview.sh [preset ...]     presets: original balanced fast off
cd /d/i3-pc || exit 1
L=testrun/user/log/shad_log.txt; F=testrun/live_cmds.txt
one() { # label sun light detail
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
    S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/seattle-CUSA00004 $S/CUSA00004
    cp tools/gfx.bak testrun/user/i3_graphics.txt
    printf "sun_shadows = $2\nlight_shadows = $3\nshadow_detail = $4\n" >> testrun/user/i3_graphics.txt
    BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 300 "45:cross,60:cross" > /dev/null; sleep ${WAIT:-115}
    for step in $(seq 1 ${STEPS:-13}); do echo "mouse=30*600" >> $F; sleep 4; done
    sleep 24
    echo shot >> $F; sleep 2
    grep -a "Flip: fps" $L | tail -8 | sed 's/.*Flip: fps //' | awk -v l=$1 '{s+=$1; n++; if ($3 > w) w = $3} END {printf "%s: %.1f FPS, worst frame %d ms\n", l, s/n, w}'
    grep -a "cpu/3s" $L | tail -1 | sed 's/.*Tick: //'
    echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
    new=$(ls -t testrun/user/screenshots/*.png 2>/dev/null | head -1)
    [ -n "$new" ] && ffmpeg -y -loglevel error -i "$new" -vf scale=640:-1 tools/cityview_$1.png
    cp tools/gfx.bak testrun/user/i3_graphics.txt
}
for p in ${@:-original balanced fast off}; do
    case $p in
    original) one original full full full;;
    balanced) one balanced half half reduced;;
    fast) one fast half off low;;
    off) one off off off full;;
    esac
done
