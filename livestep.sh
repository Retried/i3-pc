#!/bin/bash
# One step of a hand-steered session started with livestart.sh: sends the given actions with a
# wait after each, then takes a screenshot and writes a 960-wide copy for a look.
#   ./livestep.sh <out.png> "<action>:<seconds to wait>" ...
# Example: ./livestep.sh /tmp/a.png "mouse=30*900:1.1" "key=w*3000:3.2"
cd /d/i3-pc || exit 1
out=$1; shift
[ "$(tasklist | grep -ci '^i3.exe')" != "0" ] || { echo "game not running"; exit 1; }
F=testrun/live_cmds.txt
for a in "$@"; do echo "${a%:*}" >> $F; sleep "${a##*:}"; done
before=$(ls testrun/user/screenshots/*.png 2>/dev/null | wc -l)
echo shot >> $F
for i in 1 2 3 4 5 6 7 8; do
    sleep 0.5
    [ "$(ls testrun/user/screenshots/*.png 2>/dev/null | wc -l)" != "$before" ] && break
done
sleep 0.5
new=$(ls -t testrun/user/screenshots/*.png 2>/dev/null | head -1)
[ -n "$new" ] || { echo "no screenshot"; exit 1; }
ffmpeg -y -loglevel error -i "$new" -vf scale=960:-1 "$out" && echo "shot $(ls testrun/user/screenshots/*.png | wc -l): $out"
grep -a "Flip: fps" testrun/user/log/shad_log.txt | tail -1 | sed 's/.*Flip: //'
