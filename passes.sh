#!/bin/bash
# Lists the fullscreen passes of the current scene and screenshots the picture with each one
# skipped: tools/pass_<n>_<hash>.png plus tools/pass_base.png. ./passes.sh [boot script]
cd /d/i3-pc || exit 1
rm -f testrun/fs_list.txt tools/pass_*.png
./livestart.sh 330 "${1:-300:cross}" > /dev/null; sleep 25; until [ "$(tasklist | grep -ci '^i3.exe')" != "0" ]; do sleep 3; done; sleep 75
F=testrun/live_cmds.txt
shot() { echo shot >> $F; sleep 1.7; f=$(ls -t testrun/user/screenshots/*.png | head -1); cp "$f" "tools/$1.png"; }
# Freeze the scene with the game's Photo Mode so only the skipped pass changes the picture:
# enable it in Options (8th row), back out, then L3.
k() { echo "key=$1" >> $F; sleep 0.7; }
if [ -z "$NOPHOTO" ]; then
    k escape; sleep 1.5; for i in 1 2 3 4 5 6 7; do k down; done; k right; sleep 0.5; shot photo_option; k lshift; sleep 1.5; k v; sleep 2.5; shot photo_mode
fi
echo listfs >> $F; sleep 5
[ -f testrun/fs_list.txt ] || { echo "no list"; exit 1; }
cat testrun/fs_list.txt | tr '\n' ' '; echo
shot pass_base
n=0
while read -r hash count; do
    n=$((n+1)); [ $n -gt 60 ] && break
    echo "skipfs=$hash" >> $F; sleep 1.0; shot "pass_$(printf %02d $n)_$hash"; echo "skipfs=clear" >> $F; sleep 0.4
    [ "$(tasklist | grep -ci '^i3.exe')" = "0" ] && { echo "game ended at $hash"; break; }
done < testrun/fs_list.txt
echo quit >> $F
