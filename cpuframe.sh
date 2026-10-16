#!/bin/bash
# Approximate render-thread CPU/frame from a completed portable benchmark suite.
# Usage: ./cpuframe.sh <suite-directory>
set -e
exec "${PYTHON3_EXECUTABLE:-python}" - "$@" <<'PY'
import json
from pathlib import Path
import re
import statistics
import sys

if len(sys.argv) != 2:
    raise SystemExit('Usage: cpuframe.sh <completed-suite-directory>')
for path in sorted(Path(sys.argv[1]).glob('*/result.json')):
    result = json.loads(path.read_text(encoding='utf-8'))
    if result['primer'] or result['profile_enabled'] or result['status'] != 'captured':
        continue
    window = path.parent/'measurement.log'
    if not window.exists():
        print(result['label'] + ': CPU/frame unavailable (no captured counter window)')
        continue
    log = window.read_text(encoding='utf-8', errors='replace')
    counters = [int(x) for x in re.findall(r'cpu/3s ms: render thread (\d+)', log)]
    if counters:
        cpu_ms = statistics.fmean(counters) / (3 * result['metrics']['average_fps'])
        print(f"{result['label']}: approximately {cpu_ms:.2f} ms render CPU/frame "
              f"({len(counters)} counter intervals; boundaries approximate)")
    else:
        print(result['label'] + ': CPU/frame unavailable')
PY
