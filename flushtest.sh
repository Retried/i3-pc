#!/bin/bash
# Does flushing the copy back at every completion signal stop the dropped draws and the crash of
# the shooting soak? Runs the soak with SOTC_FLUSH_MASK=63 and with the default, alternating,
# and prints for each: alive or died, dropped indirect draws, mean frame rate, copy-back time
# and flushes per 3 s. Keeps each log as tools/flushtest_<label>.log. Stops between runs when
# HOLD appears or a Shadow of the Colossus process runs. About 5.5 minutes a run.
#   ./flushtest.sh [runs of each, default 2] [extra VAR=value for the flushed runs]
cd /d/i3-pc || exit 1
n=${1:-2}; shift
L=testrun/user/log/shad_log.txt
one() { # label, variables...
    label=$1; shift
    [ -f HOLD ] && { echo "HOLD set, stopping"; return 1; }
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy, stopping"; return 1; }
    rm -f SLOT_DONE
    BIN=${BIN:-/d/i3-pc/bin-release} ./shootsoak.sh $label "$@" 2>&1 | grep -E "^$label:|Unhandled" | cut -c1-150
    cp $L tools/flushtest_$label.log
    echo "$label: dropped $(grep -a -c 'Dropped indirect' $L), $(tail -1 livestart.log)"
    grep -a "Flip: fps" $L | sed 's/.*fps \([0-9.]*\).*/\1/' | awk -v l=$label '{s+=$1; n++} END {if (n) printf "%s: mean flip rate %.1f over %d samples\n", l, s/n, n}'
    grep -a "time/3s" $L | sed 's/.*mirror \([0-9]*\) flushes \([0-9]*\).*/\1 \2/' | awk -v l=$label '{s+=$1; f+=$2; n++} END {if (n) printf "%s: copy back %.0f ms and %.0f flushes per 3 s\n", l, s/n, f/n}'
    taskkill //IM i3.exe //F > /dev/null 2>&1; touch SLOT_DONE; sleep 4
}
if [ -n "$MASKS" ]; then
    # MASKS="46 58 43": one soak for each flush mask instead (42 is the default: end of pipe,
    # submit, immediate; +1 end of sequence, +4 release, +16 fence).
    for m in $MASKS; do one mask$m SOTC_FLUSH_MASK=$m || break; done
else
for i in $(seq 1 $n); do
    one flush$i SOTC_FLUSH_MASK=63 "$@" || break
    one plain$i || break
done
fi
date +%H:%M:%S
