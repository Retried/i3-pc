#!/bin/bash
# One set of menu pictures per language: start screen, Options page, Graphics page, with the
# console language of the test profile set to each language the game ships. Pictures go to
# tools/lang_<id>_<n>.png (960 wide); the profile's own language is put back at the end.
# Direct launch: only in an agreed slot. About 75 seconds a language.
#   ./langshots.sh [ids, default all fourteen]
cd /d/i3-pc || exit 1
C=testrun/user/config.json
cp $C tools/config.langshots.bak
setlang() { tools/venv/Scripts/python - "$1" <<'PY'
import json, sys
p = 'D:/i3-pc/testrun/user/config.json'
c = json.load(open(p, encoding='utf-8'))
c['General']['console_language'] = int(sys.argv[1])
json.dump(c, open(p, 'w', encoding='utf-8'), indent=4)
PY
}
S=testrun/user/home/1000/savedata; rm -rf $S/CUSA00004; cp -rp fixtures/fishcannery-CUSA00004 $S/CUSA00004
for id in ${@:-1 2 3 4 5 6 7 8 12 13 14 15 16 19}; do
    [ -f HOLD ] && { echo "HOLD set, stopping"; break; }
    [ "$(tasklist | grep -ci -E 'shadps4|sotc_ab|ShadowOfTheColossus|^i3.exe')" = "0" ] || { echo "busy, stopping"; break; }
    rm -f SLOT_DONE testrun/user/screenshots/*.png
    setlang $id
    # Start screen; down three rows to Options, open; open Graphics (first row); scroll to the end.
    a="38:shotui,39:pad=dpdown,40:pad=dpdown,41:pad=dpdown,42:pad=a,44:shotui,45:pad=a,47:shotui"
    for i in $(seq 0 15); do a="$a,$((48 + i)):pad=dpdown"; done
    a="$a,65:shotui"
    if [ -n "$CONTROLS" ]; then
        # CONTROLS=1: the Controls page instead (second row of Options): top, then scrolled twice.
        a="38:shotui,39:pad=dpdown,40:pad=dpdown,41:pad=dpdown,42:pad=a,44:pad=dpdown,45:pad=a,47:shotui"
        for i in $(seq 0 11); do a="$a,$((48 + i)):pad=dpdown"; done
        a="$a,61:shotui"
        for i in $(seq 0 13); do a="$a,$((62 + i)):pad=dpdown"; done
        a="$a,77:shotui"
    fi
    (cd testrun && env SOTC_HEADLESS=1 SOTC_MUTE=1 I3_SKIP_FIRST_RUN=1 I3_START_SCREEN=1 SOTC_VPAD=1 SOTC_SCRIPT="$a" \
        "${BIN:-/d/i3-pc/bin}/i3.exe" -f false --game "D:/Games/CUSA00004/eboot.bin" > /dev/null 2>&1 &)
    sleep ${RUN:-85}; taskkill //IM i3.exe //F > /dev/null 2>&1; sleep 2
    n=0; for f in $(ls -tr testrun/user/screenshots/*.png 2>/dev/null); do n=$((n + 1)); ffmpeg -y -loglevel error -i "$f" -vf scale=960:-1 tools/lang${CONTROLS:+c}_${id}_$n.png; done
    echo "language $id: $n pictures"
    touch SLOT_DONE
done
cp tools/config.langshots.bak $C
date +%H:%M:%S
