#!/bin/bash
# Showcase capture from the installed save: screenshots into showcase/ and a recorded clip.
cd /d/i3-pc || exit 1
S=showcase; mkdir -p $S; F=testrun/live_cmds.txt
grab() { sleep "${2:-1.2}"; echo "${3:-shot}" >> $F; sleep 1.6; f=$(ls -t testrun/user/screenshots/*.png 2>/dev/null | head -1); [ -n "$f" ] && cp "$f" "$S/$1.png" && echo "saved $1"; }
./livestart.sh 330 "200:cross" > /dev/null
sleep 25; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done
sleep 42; echo "key=down" >> $F; grab 01_title 2
echo "key=space" >> $F; sleep 14; echo "key=space" >> $F; sleep 40
[ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && { echo "session ended early"; tail -2 livestart.log; exit 1; }
grab 02_outdoors_crash_site 1
echo "rec=on" >> $F
echo "key=w*5000" >> $F; sleep 3; echo "mouse=18*1500" >> $F; sleep 3
echo "key=space" >> $F; sleep 1.5; echo "key=w*4000" >> $F; echo "key=lshift" >> $F; sleep 2; echo "mouse=-22*1800" >> $F; sleep 3
echo "key=a*2500" >> $F; sleep 3; echo "key=w*6000" >> $F; sleep 2; echo "key=space" >> $F; sleep 2; echo "mouse=15*2000" >> $F; sleep 3
echo "key=d*3000" >> $F; echo "key=f" >> $F; sleep 3.5; echo "key=s*2500" >> $F; echo "mouse=-15*2500" >> $F; sleep 3.5
echo "key=w*5000" >> $F; sleep 2.5; echo "key=space" >> $F; sleep 3
echo "rec=off" >> $F
grab 03_exploring 1
echo "key=escape" >> $F; grab 04_options_keyboard_icons 2.5
echo "key=down" >> $F; sleep 1; echo "key=down" >> $F; sleep 1; echo "key=space" >> $F; grab 05_load_dialog 3 shotui
echo "key=enter" >> $F; grab 06_after_load_no 4 shotui
grab 07_after_load_later 5 shotui
echo quit >> $F
ls -la testrun/user/capture | awk '{print $5,$9}'
