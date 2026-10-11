#!/bin/bash
# No-save start only (direct launch, ignores HOLD: only in an agreed slot); keeps the log.
cd /d/i3-pc/testrun || exit 1
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=user/home/1000/savedata
rm -f user/screenshots/*.png; rm -rf $S/CUSA00004
(env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_SCRIPT="38:shotui,41:key=enter,58:shotui,74:shotui" \
    "${BIN:-/d/i3-pc/bin-release}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
sleep 85; echo "alive at 85 s: $(tasklist | grep -ci '^i3.exe')"; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
cp user/log/shad_log.txt /d/i3-pc/tools/nosave.log
rm -rf $S/CUSA00004; cp -rp ../fixtures/fishcannery-CUSA00004 $S/CUSA00004
n=0
for f in $(ls -tr user/screenshots/*.png 2>/dev/null); do n=$((n + 1)); cp "$f" /d/i3-pc/tools/st4_$n.png; done
echo "screenshots: $n; flips logged: $(grep -a -c 'Flip: fps' /d/i3-pc/tools/nosave.log)"
grep -a "Unhandled\|Assert\|Critical" /d/i3-pc/tools/nosave.log | tail -3 | cut -c1-220
