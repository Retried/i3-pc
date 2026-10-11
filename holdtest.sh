#!/bin/bash
# Repeated start-screen boots: does the picture keep drawing while the game is held?
#   ./holdtest.sh [boots]      (BIN=<folder> picks the build, test binary by default)
# Each boot stays 20 seconds on the start screen with a screenshot request every 4 seconds and
# then quits by itself, so the log is complete. Prints the screenshots written and how often the
# hold had to be renewed. Direct launch: only in an agreed slot.
cd /d/i3-pc/testrun || exit 1
for n in $(seq 1 "${1:-6}"); do
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
    rm -f user/screenshots/*.png
    [ -n "$COPY" ] && { rm -rf user/home/1000/savedata/CUSA00004; cp -rp ../fixtures/$COPY-CUSA00004 user/home/1000/savedata/CUSA00004; }
    (env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_VPAD=1 \
        SOTC_SCRIPT="12:shotui,16:shotui,20:shotui,24:shotui,28:shotui,30:quit" \
        "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    sleep 42
    alive=$(tasklist | grep -ci '^i3.exe')
    taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 3
    echo "boot $n: screenshots $(ls user/screenshots/*.png 2>/dev/null | wc -l) of 5, hold renewed $(grep -a -c 'hold renewed' user/log/shad_log.txt), still running at the end: $alive"
done
