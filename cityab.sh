#!/bin/bash
# Before/after comparison of two optimized builds: the slow Seattle view (cityview.sh, Shadow
# Preset Original) twice each, alternating, then the crash site (ft.sh chase) once each as a
# check that nothing else got slower. About 22 minutes. Stops between runs when HOLD appears.
#   ./cityab.sh <old folder> <new folder>      result in tools/cityab_result.txt
cd /d/i3-pc || exit 1
old=${1:-/d/i3-pc/bin-fix2}; new=${2:-/d/i3-pc/bin-fix3}
[ -f HOLD ] && { echo "HOLD is set"; exit 1; }
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
rm -f SLOT_DONE
{
for n in 1 2; do
    for v in old new; do
        [ -f HOLD ] && break 2
        echo "== city $v $n"
        BIN=${!v} ./cityview.sh original | sed "s/^original/$v$n/"
    done
done
for v in old new; do
    [ -f HOLD ] && break
    echo "== crash site $v"
    BIN=${!v} ./ft.sh cityab_$v chase | head -1
    grep -a -c "Dropped indirect\|Unhandled" tools/ft_cityab_$v.log | sed "s/^/dropped or unhandled lines: /"
done
} 2>&1 | tee tools/cityab_result.txt
sleep 3; taskkill //IM i3.exe //F > /dev/null 2>&1
touch SLOT_DONE; date +%H:%M:%S
