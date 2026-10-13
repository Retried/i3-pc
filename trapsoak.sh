#!/bin/bash
# Shooting soaks until one dies, to read the crash aid (the game object at the fault and the
# copy-back writes that touched it). Frame clock of the test profile set to CLOCK (default 144)
# for the runs and put back afterwards. Stops at HOLD or when a SotC process runs.
#   ./trapsoak.sh [runs, default 3]      logs: tools/trap_<n>.log
cd /d/i3-pc || exit 1
C=testrun/user/config.json; L=testrun/user/log/shad_log.txt
cp $C tools/config.trapsoak.bak
tools/venv/Scripts/python -c "
import json; p='D:/i3-pc/testrun/user/config.json'; c=json.load(open(p,encoding='utf-8')); c['GPU']['vblank_frequency']=${CLOCK:-144}; json.dump(c,open(p,'w',encoding='utf-8'),indent=4)"
for n in $(seq 1 ${1:-3}); do
    [ -f HOLD ] && { echo "HOLD set, stopping"; break; }
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy, stopping"; break; }
    rm -f SLOT_DONE; v=trapx$n
    BIN=${BIN:-/d/i3-pc/bin-fix6} ./shootsoak.sh $v 2>&1 | grep -E "^$v:" | cut -c1-120
    cp $L tools/trap_$v.log
    echo "$v: dropped $(grep -a -c 'Dropped indirect' $L), $(tail -1 livestart.log)"
    taskkill //IM i3.exe //F > /dev/null 2>&1; touch SLOT_DONE; sleep 4
    if grep -a -q "Unhandled Exception" tools/trap_$v.log; then
        grep -a "rdi 0x\|copy back wrote\|copy back writes near" tools/trap_$v.log | cut -c1-260 | head -30
        break
    fi
done
cp tools/config.trapsoak.bak $C
date +%H:%M:%S
