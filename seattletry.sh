#!/bin/bash
# One recorded attempt at a route from a save: boots the save, records while the given actions
# run, and writes contact sheets (two pictures a second, 24 to a sheet) so the whole attempt can
# be looked at afterwards. Optimized build. Direct launch: only in an agreed slot.
#   FX=<fixture, default seattle> ./seattletry.sh <label> "<action>:<seconds to wait>" ...
#   sheets: tools/try_<label>_<n>.png
cd /d/i3-pc || exit 1
label=$1; shift
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/${FX:-seattle}-CUSA00004 $S/CUSA00004
cp tools/gfx.bak testrun/user/i3_graphics.txt
# SUN, LIGHT, DETAIL add a Shadow Preset to the graphics file (Balanced: half half reduced).
[ -n "$SUN" ] && printf "sun_shadows = $SUN\nlight_shadows = $LIGHT\nshadow_detail = $DETAIL\n" >> testrun/user/i3_graphics.txt
rm -rf testrun/user/capture; rm -f tools/try_${label}_*.png
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 400 "45:cross,60:cross" > /dev/null; sleep ${WAIT:-115}
F=testrun/live_cmds.txt
echo "rec=on" >> $F; sleep 1
for a in "$@"; do echo "${a%:*}" >> $F; sleep "${a##*:}"; done
echo "rec=off" >> $F; sleep 2
grep -a "Flip: fps" testrun/user/log/shad_log.txt | tail -3 | sed 's/.*Flip: //' | tr '\n' ';'; echo
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
read w h rate < testrun/user/capture/frames.txt
ffmpeg -y -loglevel error -f rawvideo -pix_fmt rgb24 -s ${w}x${h} -r $rate -i testrun/user/capture/frames.rgb \
    -vf "fps=${FPS:-2},scale=${TW:-320}:-1,tile=${TILE:-6x4}" tools/try_${label}_%d.png
ls tools/try_${label}_*.png
[ -n "$KEEP" ] || rm -rf testrun/user/capture
