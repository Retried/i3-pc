#!/bin/bash
# Start-screen watch: one boot of the test binary left on the start screen, a screenshot request
# every 5 seconds, and every 10 seconds the screenshot count, the processor time used and the
# thread count. Shows whether the picture stops while the process lives. Direct launch: only in
# an agreed slot.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
rm -f user/screenshots/*.png
s=""; for t in 20 25 30 35 40 45 50 55 60 65 70 75 80 85; do s="$s,$t:shotui"; done
(env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_VPAD=1 SOTC_SCRIPT="${s#,}" \
    "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
for i in 1 2 3 4 5 6 7 8 9; do
    sleep 10
    p=$(powershell -NoProfile -Command "Get-Process i3 -EA SilentlyContinue | % { '{0:F0} s cpu, {1} threads' -f \$_.TotalProcessorTime.TotalSeconds, \$_.Threads.Count }")
    echo "t=$((i * 10)) shots=$(ls user/screenshots/*.png 2>/dev/null | wc -l) $p"
done
echo quit >> live_cmds.txt; sleep 6; taskkill //IM i3.exe //F > /dev/null 2>&1
grep -a "Unhandled\|Assert\|Critical" user/log/shad_log.txt | tail -3 | cut -c1-200
tail -2 user/log/shad_log.txt | cut -c1-200
