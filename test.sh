#!/bin/bash
# Headless test run: ./test.sh <seconds> [VAR=value ...]
cd /d/i3-pc/testrun || exit 1
secs=$1; shift
# A HOLD file parks test runs (used to hand the machine to the SotC session for a while).
while [ -f /d/i3-pc/HOLD ]; do sleep 5; done
if [ "$(tasklist | grep -ci "^i3.exe")" != "0" ]; then echo "REFUSED: a game instance is running"; exit 1; fi
# SotC has priority and two instances do not fit in memory: never start next to one, never
# start when memory is short, and give way at once if either changes while running.
memfree_mb() { while read -r k v _; do [ "$k" = "MemFree:" ] && { echo $((v / 1024)); return; }; done < /proc/meminfo; }
if [ "$(tasklist | grep -ciE 'shadps4|sotc_ab|ShadowOfTheColossus')" != "0" ]; then echo "REFUSED: SotC is running"; exit 1; fi
# The user's own game session shares this profile folder (saves, settings): never run beside it.
if [ "$(tasklist | grep -ci 'inFAMOUS Second')" != "0" ]; then echo "REFUSED: the user is playing inFAMOUS"; exit 1; fi
# Snipping Tool crashed inside the AMD driver three times on 2026-10-10 and each crash reset the
# display driver (monitor lost signal): never use the GPU while it is open.
if [ "$(tasklist | grep -ci 'SnippingTool')" != "0" ]; then echo "REFUSED: Snipping Tool is open"; exit 1; fi
if [ "$(memfree_mb)" -lt 9000 ]; then echo "REFUSED: only $(memfree_mb) MB RAM free"; exit 1; fi
bin=${BIN:-/d/i3-pc/bin}
exe=$bin/i3.exe
env SOTC_HEADLESS=1 ${MUTE-SOTC_MUTE=1} ${FIRSTRUN-I3_SKIP_FIRST_RUN=1} "$@" "$exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &
pid=$!
for ((i = 0; i < secs; i++)); do
    kill -0 $pid 2>/dev/null || break
    if [ "$(tasklist | grep -ciE 'shadps4|sotc_ab|ShadowOfTheColossus')" != "0" ]; then echo "YIELDED: SotC started"; break; fi
    if [ "$(tasklist | grep -ci 'inFAMOUS Second')" != "0" ]; then echo "YIELDED: the user started inFAMOUS"; break; fi
    if [ "$(memfree_mb)" -lt 3000 ]; then echo "YIELDED: memory low"; break; fi
    sleep 1
done
if kill -0 $pid 2>/dev/null; then
    kill -9 $pid 2>/dev/null
    sleep 2
    # The shell's kill does not always reach the Windows process: end it by its own name
    # (never by the SotC names).
    if [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; then
        taskkill //IM i3.exe //F > /dev/null 2>&1
        sleep 2
        [ "$(tasklist | grep -ci '^i3.exe')" != "0" ] && echo "STUCK: i3.exe did not exit"
    fi
fi
echo "ran ${i}s, flips $(grep -c 'Flip: fps' user/log/shad_log.txt)"
if grep -q "Critical" user/log/shad_log.txt; then
    mkdir -p user/log/crashes && cp user/log/shad_log.txt "user/log/crashes/$(date +%m%d_%H%M%S).txt"
fi
grep -n "Critical" -A1 user/log/shad_log.txt | head -6 | cut -c1-300
