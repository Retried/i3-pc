#!/bin/bash
# Benchmark: fixed scenes x display configurations, 30 s of frame times each.
# ./bench.sh            all scenes and configurations -> showcase/benchmark_raw.csv
# SCENES="roam" CONFIGS="1080p" ./bench.sh   a subset
# Needs the test saves in fixtures/ and gives way to SotC like every other test run.
cd /d/i3-pc || exit 1
S=testrun/user/home/1000/savedata
OUT=showcase/benchmark_raw.csv
[ -f "$OUT" ] || echo "scene,config,frames,avg_fps,low1_fps,low01_fps,worst_ms,ram_mb,vram_mb" > "$OUT"
cp testrun/user/config.json tools/config.bench.bak
cp testrun/user/i3_graphics.txt tools/effects.bench.bak 2>/dev/null
rm -rf "$S/CUSA00004.benchkeep"; mv "$S/CUSA00004" "$S/CUSA00004.benchkeep"

setcfg() { # width height fsr
    python -I - "$1" "$2" "$3" <<'PY'
import json, sys
p = 'D:/i3-pc/testrun/user/config.json'
c = json.load(open(p))
c['GPU']['window_width'] = int(sys.argv[1]); c['GPU']['window_height'] = int(sys.argv[2])
c['GPU']['fsr_enabled'] = sys.argv[3] == '1'; c['GPU']['vblank_frequency'] = 120
c['GPU']['present_mode'] = 'Immediate'
json.dump(c, open(p, 'w'), indent=2)
PY
}

for scene in ${SCENES:-billboard cannery roam}; do
    case $scene in
        billboard) save=""; script="45:cross,60:cross,75:cross,95:cross,110:bench=on,140:bench=off"; secs=146;;
        cannery) save=fixtures/earlygame-CUSA00004; script="45:cross,60:cross,100:bench=on,130:bench=off"; secs=136;;
        roam) save=fixtures/after-crash-CUSA00004; script="85:bench=on,115:bench=off"; secs=121;;
    esac
    for config in ${CONFIGS:-1080p 1440p_fsr 2160p_fsr 1080p_minimal}; do
        case $config in
            1080p) setcfg 1920 1080 0; fx=on;;
            1440p_fsr) setcfg 2560 1440 1; fx=on;;
            2160p_fsr) setcfg 3840 2160 1; fx=on;;
            1080p_minimal) setcfg 1920 1080 0; fx=off;;
        esac
        printf 'antialiasing = %s\nreflections = %s\nglow = %s\n' $fx $fx $fx > testrun/user/i3_graphics.txt
        for attempt in 1 2 3 4 5 6 7 8; do
            until [ "$(tasklist | grep -ciE 'shadps4|ShadowOfTheColossus|inFAMOUS Second|^i3.exe')" = "0" ]; do sleep 3; done
            rm -rf "$S/CUSA00004"; [ -n "$save" ] && cp -r "$save" "$S/CUSA00004"
            rm -f testrun/bench_frametimes.txt tools/bench_mem.txt
            # Memory use of the game process, sampled near the end of the measurement.
            ( sleep $((secs - 12)); powershell -NoProfile -Command "\$p = Get-Process i3 -ErrorAction SilentlyContinue; if (\$p) { [int](\$p.WorkingSet64/1MB) }" > tools/bench_mem.txt 2>/dev/null ) &
            out=$(./test.sh $secs SOTC_SCRIPT="$script" 2>&1 | grep -v Killed | tail -1)
            wait
            echo "$out" | grep -q "YIELDED\|REFUSED" || break
        done
        python -I - "$scene" "$config" "$OUT" <<'PY'
import sys
scene, config, out = sys.argv[1:4]
try:
    t = [float(x) for x in open('D:/i3-pc/testrun/bench_frametimes.txt').read().split()]
except OSError:
    t = []
try:
    ram = open('D:/i3-pc/tools/bench_mem.txt').read().split()[0]
except (OSError, IndexError):
    ram = ''
if len(t) < 100:
    row = f'{scene},{config},{len(t)},,,,,{ram},'
else:
    t = t[5:]
    s = sorted(t, reverse=True)
    avg = 1000 * len(t) / sum(t)
    low1 = 1000 / (sum(s[:max(1, len(s) // 100)]) / max(1, len(s) // 100))
    low01 = 1000 / (sum(s[:max(1, len(s) // 1000)]) / max(1, len(s) // 1000))
    row = f'{scene},{config},{len(t)},{avg:.1f},{low1:.1f},{low01:.1f},{s[0]:.0f},{ram},'
open(out, 'a').write(row + '\n')
print(row)
PY
    done
done
rm -rf "$S/CUSA00004"; mv "$S/CUSA00004.benchkeep" "$S/CUSA00004"
cp tools/config.bench.bak testrun/user/config.json
[ -f tools/effects.bench.bak ] && cp tools/effects.bench.bak testrun/user/i3_graphics.txt
echo "bench done"
