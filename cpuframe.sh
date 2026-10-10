#!/bin/bash
# Render-thread CPU per frame in the cannery scene (independent of the game's pacing tier).
# ./cpuframe.sh label [VAR=value ...]
cd /d/i3-pc || exit 1
label=$1; shift
r=$(env X=1 "$@" SCENES=cannery CONFIGS=1080p ./bench.sh | grep "^cannery")
paste -d' ' <(grep "cpu/3s" testrun/user/log/shad_log.txt | tail -7 | awk '{print $(NF-2)}') <(grep "Flip: fps" testrun/user/log/shad_log.txt | tail -7 | awk '{print $7}') |
    awk -v l="$label" -v r="$r" '{ if ($2>0) { n++; s+=$1/($2*3); f+=$2 } } END { if (n) printf "%s: %.1f ms thread CPU per frame, %.1f fps (%s)\n", l, s/n, f/n, r }'
