#!/bin/bash
# Second crash-site comparison: optimized build of the working tree (cheaper changed-bytes
# copy back) against the build before the copy-back changes, alternating (about 20 minutes
# with the link). Same guards as crashtest.sh.
cd /d/i3-pc || exit 1
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
free=$(powershell -NoProfile -Command "[int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)")
[ "$free" -ge 8 ] || { echo "only $free GB free"; exit 1; }
rm -f SLOT_DONE
cmd //c "D:\i3-pc\build-lto.bat" 2>&1 | grep -E "error|FAILED|Linking" | head -5
mkdir -p bin-fix2; cp runtime/Build/x64-Clang-Release/shadps4.exe bin-fix2/i3.exe
{
for n in 1 2; do
    BIN=/d/i3-pc/bin-old ./ft.sh ab2_old$n chase | head -3
    BIN=/d/i3-pc/bin-fix2 ./ft.sh ab2_new$n chase | head -3
done
for l in ab2_old1 ab2_new1 ab2_old2 ab2_new2; do
    echo "$l: copy back $(grep -a 'time/3s' tools/ft_$l.log | sed 's/.*mirror \([0-9]*\).*/\1/' | awk '{s+=$1;n++} END {if(n) printf "%.0f", s/n}') ms per 3 s"
done
} 2>&1 | tee tools/ab2_result.txt
sleep 5; taskkill //IM i3.exe //F > /dev/null 2>&1
touch SLOT_DONE; date +%H:%M:%S
