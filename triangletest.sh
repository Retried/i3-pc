#!/bin/bash
# What Options, then Triangle, do in the game at a given save: screenshots after each press
# (tools/tt_<fixture>_N.png). Buttons go straight to the game. Direct launch: only in an agreed slot.
#   ./triangletest.sh [fixture, default fishcannery]
cd /d/i3-pc || exit 1
fx=${1:-fishcannery}
[ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy"; exit 1; }
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/$fx-CUSA00004 $S/CUSA00004
BIN=${BIN:-/d/i3-pc/bin} ./livestart.sh 300 "45:cross,60:cross" > /dev/null; sleep 110
F=testrun/live_cmds.txt
k() { echo "$1" >> $F; sleep "$2"; }
k "shotui" 1; k "options" 2.5; k "shotui" 1; k "triangle" 2.5; k "shotui" 1
k "down" 1; k "shotui" 1; k "circle" 2; k "shotui" 1; k "circle" 2; k "shotui" 1
echo quit >> $F; sleep 8; taskkill //IM i3.exe //F > /dev/null 2>&1
n=0; for f in $(ls -tr testrun/user/screenshots/*.png); do n=$((n + 1)); cp "$f" tools/tt_${fx}_$n.png; done
echo "$fx screenshots: $n"
