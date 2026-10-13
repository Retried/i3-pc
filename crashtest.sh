#!/bin/bash
# Test of the two copy-back fixes against the shooting-soak crash: optimized build of the
# working tree, three soaks with both fixes, one with whole-range copy back (I3_MIRROR_WHOLE=1,
# draw-argument copy back still on), one with both off, two of the installed build as the
# baseline. After each soak: mean frame rate and mean copy-back time per 3 s from its log.
# About 35 minutes. Refuses to start beside a Shadow of the Colossus run, while D:\i3-pc\HOLD
# is set, or with less than 8 GB of free memory. Writes SLOT_DONE at the end.
cd /d/i3-pc || exit 1
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
free=$(powershell -NoProfile -Command "[int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)")
[ "$free" -ge 8 ] || { echo "only $free GB free"; exit 1; }
rm -f SLOT_DONE
cmd //c "D:\\i3-pc\\build-lto.bat" 2>&1 | grep -E "error|FAILED|Linking" | head -5
mkdir -p bin-fix; cp runtime/Build/x64-Clang-Release/shadps4.exe bin-fix/i3.exe
L=testrun/user/log/shad_log.txt
# shootsoak.sh takes the label first and passes the rest to the game's environment.
run() { label=$1; bin=$2; shift; shift; BIN=$bin soak_env "$label" "$@"; }
soak_env() {
    label=$1; shift
    ./shootsoak.sh "$label" "$@" 2>&1 | grep -E "^$label:|Unhandled"
    grep -a "Flip: fps" $L | sed 's/.*fps \([0-9.]*\).*/\1/' | awk -v l=$label '{s+=$1; n++} END {if (n) printf "%s: mean flip rate %.1f over %d samples\n", l, s/n, n}'
    grep -a "time/3s" $L | sed 's/.*mirror \([0-9]*\).*/\1/' | awk -v l=$label '{s+=$1; n++} END {if (n) printf "%s: copy back %.0f ms per 3 s\n", l, s/n}'
    grep -a "Flip: fps" $L | sed 's/.*worst \([0-9]*\) ms.*/\1/' | awk -v l=$label '{if ($1 > m) m = $1; if ($1 > 50) a++; if ($1 > 100) b++} END {printf "%s: worst frame %d ms, seconds with a frame over 50 ms %d, over 100 ms %d\n", l, m, a, b}'
    cp $L tools/crashtest_$label.log
}
for n in 1 2 3; do run fix$n /d/i3-pc/bin-fix; done
run whole /d/i3-pc/bin-fix I3_MIRROR_WHOLE=1
run nofix /d/i3-pc/bin-fix I3_MIRROR_WHOLE=1 I3_NO_ARG_MIRROR=1
for n in 1 2; do run base$n /d/i3-pc/bin-release; done
sleep 5; taskkill //IM i3.exe //F > /dev/null 2>&1
touch SLOT_DONE; date +%H:%M:%S
