#!/bin/bash
# Starts a live-steered session (see live.sh) in the background: ./livestart.sh <seconds> [boot script] [VAR=value ...]
# Waits for a slot with no SotC instance first. Default boot script starts a new game.
cd /d/i3-pc || exit 1
until [ "$(tasklist | grep -ci "^i3.exe")" = "0" ]; do sleep 2; done
secs=${1:-300}; script=${2:-45:cross,60:cross,75:cross,95:cross}; shift; shift
: > testrun/live_cmds.txt
rm -f testrun/user/screenshots/*.png
(./waitrun.sh "$secs" SOTC_SCRIPT_FILE="D:/i3-pc/testrun/live_cmds.txt" SOTC_SCRIPT="$script" "$@" > livestart.log 2>&1 &)
echo started
