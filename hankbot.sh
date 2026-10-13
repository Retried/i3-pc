#!/bin/bash
# The first boss fight steered from screenshots (tools/hankbot.py): boots the fight save, runs
# through the fence, then lets the script fight for the given time. Optimized build. Direct
# launch: only in an agreed slot. Contact sheets of every fifth screenshot of the bot in
# tools/try_hank_N.png.   ./hankbot.sh [seconds, default 150]
cd /d/i3-pc || exit 1
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
secs=${1:-150}
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/defeathank-CUSA00004 $S/CUSA00004
cp tools/gfx.bak testrun/user/i3_graphics.txt
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh $((secs + 190)) "45:cross,60:cross" > /dev/null; sleep ${WAIT:-130}
F=testrun/live_cmds.txt
echo "key=w*2000" >> $F; sleep 0.6; echo "key=lshift*300" >> $F; sleep 1.6
echo "key=w*2500" >> $F; sleep 2.6
rm -f tools/try_hank_*.png tools/hb_*.png tools/hbseq_*.png
tools/venv/Scripts/python tools/hankbot.py $((secs * 10 / 12)) | tail -25
grep -a -c "Dropped indirect\|Unhandled" testrun/user/log/shad_log.txt
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
ffmpeg -y -loglevel error -i tools/hbseq_%03d.png -vf "tile=6x5" tools/try_hank_%d.png 2>/dev/null     || echo "no pictures to tile"
rm -f tools/hbseq_*.png
ls -la --time-style=+%H:%M testrun/user/home/1000/savedata/CUSA00004/*/ 2>/dev/null | grep -v "^total" | awk '{print $6, $7}' | sort | tail -4
