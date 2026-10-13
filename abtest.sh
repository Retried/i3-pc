#!/bin/bash
# Crash-site frame rate, build before the copy-back changes against the build with them, and
# the build with each change switched off (about 15 minutes). Same guards as crashtest.sh.
cd /d/i3-pc || exit 1
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
rm -f SLOT_DONE
{
BIN=/d/i3-pc/bin-old ./ft.sh ab_old chase | head -3
BIN=/d/i3-pc/bin-fix ./ft.sh ab_new chase | head -3
BIN=/d/i3-pc/bin-fix ./ft.sh ab_whole chase I3_MIRROR_WHOLE=1 | head -3
BIN=/d/i3-pc/bin-fix ./ft.sh ab_off chase I3_MIRROR_WHOLE=1 I3_NO_ARG_MIRROR=1 | head -3
BIN=/d/i3-pc/bin-old ./ft.sh ab_old2 chase | head -3
} 2>&1 | tee tools/ab_result.txt
sleep 5; taskkill //IM i3.exe //F > /dev/null 2>&1
touch SLOT_DONE; date +%H:%M:%S
