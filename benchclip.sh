#!/bin/bash
# One benchmark clip with the performance panel in the picture:
#   ./benchclip.sh <label> <fixture> <sun> <light> <detail> <route> "<scene text>" "<settings text>" ["<uncaptured fps text>"]
# route: stand | road | city. Writes showcase/bench_<label>.mp4. Optimized build.
cd /d/i3-pc || exit 1
label=$1; fx=$2; route=$6; scene=$7; settings=$8; plain=$9
[ "$(tasklist | grep -ci -E 'ShadowOfTheColossus|shadps4|sotc_ab')" = "0" ] || { echo "SOTC up"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/$fx-CUSA00004 $S/CUSA00004
cp tools/gfx.bak testrun/user/i3_graphics.txt
printf "sun_shadows = $3\nlight_shadows = $4\nshadow_detail = $5\n" >> testrun/user/i3_graphics.txt
rm -rf testrun/user/capture; rm -f testrun/bench_frametimes.txt testrun/perf_samples.csv
BIN=${BIN:-/d/i3-pc/bin-release} ./livestart.sh 400 "45:cross,60:cross" > /dev/null; sleep 25
until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done
(powershell -NoProfile -ExecutionPolicy Bypass -File tools/perfsample.ps1 > /dev/null 2>&1 &)
sleep 75
F=testrun/live_cmds.txt
k() { echo "$1" >> $F; sleep "$2"; }
printf "rec=on\nbench=on\n" >> $F
case $route in
road)
    k "key=w*2000" 2.1; k "mouse=30*800" 1; for i in 1 2 3; do k "key=w*2500" 2.6; done
    k "mouse=30*700" 1; for i in 1 2 3 4; do k "key=w*3000" 3.1; done;;
city)
    for r in 1 2 3; do
        k "key=w*3000" 1.5; k "key=lshift" 1.6; k "key=w*3000" 1.5; k "key=space" 1.6
        k "mouse=30*900" 1.1; k "key=rightbutton*1500" 0.3; k "key=leftbutton" 0.6; k "key=leftbutton" 0.8
        k "key=w*2500" 2.6; k "mouse=-30*500" 0.7
    done;;
*)
    k "mouse=12*4000" 5; sleep 6; k "mouse=-12*4000" 5; sleep 8;;
esac
printf "bench=off\nrec=off\n" >> $F; sleep 2
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
cp tools/gfx.bak testrun/user/i3_graphics.txt
# 1920x1080 clip with the readout, then the 1280x720 copy (15 MB at most for 24 s: 4500 kbit/s).
tools/venv/Scripts/python tools/benchvideo.py testrun showcase/bench_${label}_1080.mp4 "$scene" "$settings" "$plain" 0 24 | tail -1 > showcase/bench_$label.txt
echo "build: $(basename ${BIN:-/d/i3-pc/bin-release})" >> showcase/bench_$label.txt
ffmpeg -y -loglevel error -i showcase/bench_${label}_1080.mp4 -vf scale=1280:720 -c:v libx264 -preset medium -b:v 4300k -maxrate 4500k -bufsize 9000k -c:a aac -b:a 128k showcase/bench_$label.mp4
ls -la showcase/bench_$label.mp4 showcase/bench_${label}_1080.mp4 | awk '{print $5, $9}'; cat showcase/bench_$label.txt
