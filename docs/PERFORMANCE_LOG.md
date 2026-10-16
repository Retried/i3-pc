# Measured performance changes

Local W3 control measurements and W4 profiling/A-B evidence are recorded below.
These do not establish gameplay gains or the effectiveness of priority-2 pipeline
cache changes. Build times and unit-test counts are not gameplay performance.

Historical project measurements are available in [BENCHMARK.md](BENCHMARK.md).
They were collected on the configuration stated in that document, including an
AMD GPU; they are not new measurements on the target NVIDIA configurations and
do not validate subsequent optimizations.

## Required entry format

For each measured change, follow [BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md)
and record:

- Date, change description and baseline/candidate main and runtime commit IDs.
- Machine and driver configuration, build settings and local patches.
- Scene, route, emulator settings and cache state.
- Raw CSV/JSON locations and number of runs on each PC.
- Baseline and candidate average FPS, 1% low, frametime distribution and variation.
- Correctness and stability results, regressions and untested configurations.
- Conclusion supported by the measurements; record inconclusive results as such.

## 2026-10-16: W3 local control baseline

One machine: Windows 11 Pro 10.0.26200, AMD Ryzen 5 7640HS (6C/12T),
31,879,192,576 bytes accessible RAM, NVIDIA RTX 4050 Laptop (6141 MiB), driver
617.42 (Windows 32.0.16.1742), Vulkan 1.4.351. No second PC is available.
Wrapper source `4c3433f74710f1725d0aa2ff7b7d4be19d06e791`, runtime
`f88d3b6f331272ce854bda5875c11386b180f94f`, clean runtime source, wrapper capture
tooling changes uncommitted during measurement. RelWithDebInfo, clang-cl 19.1.5,
LTO off; executable SHA-256
`DC983DB65BE1F9585E183EA2D1F5B6F59C673728FC8E264A015500CA1F729EE0`.

CUSA00004 APP_VER/VERSION 01.07 after the documented local metadata repair.
Only 0-percent opening saves are available. Static title/Continue, no input or
camera motion, 35 s warm-up then 30 s capture, hidden SDL window/dummy audio,
1920x1080 internal/window requested and 1920x1080 screenshots confirmed,
Immediate presentation, 144 Hz frame clock. Effects: AA off, reflections/glow on,
sun/light shadows half, shadow detail reduced. Validation disabled for timing;
Khronos layer unavailable. Installed implicit layers and driver cache unchanged.
Cold means empty emulator cache; warm repeats clone one frozen primer cache.

| Emulator cache | N | Average FPS mean (range) | 1% low mean | Median ms mean | p95 ms mean | p99 ms mean | Worst ms max |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cold | 3 | 67.95 (66.74-69.08) | 40.56 | 14.016 | 20.849 | 21.559 | 55.553 |
| Warm | 3 | 68.35 (67.83-68.74) | 44.43 | 13.997 | 20.832 | 21.521 | 28.018 |

These are arithmetic means of per-run metrics, not pooled frame percentiles.
The approximately 0.6-percent FPS difference is within repeat variation and
does not establish a cache benefit. All six measured runs and the excluded
primer exited 0. Logs confirm NVIDIA and APP_VER 01.07, with no matched critical,
device-loss or assertion message. Twelve start/end screenshots show the same
title control without an evident visual difference; this cannot validate game
effects, scene transitions, readbacks or long-session stability. Original saves
were preserved. Missing GPU frame times remain null.

Mean telemetry across repeats: cold/warm process CPU 27.49/27.89 percent of
12 logical CPUs, busiest thread 97.59/97.73 percent of one CPU, whole-card NVIDIA
load 52.90/53.36 percent, VRAM 4530.67/4512.10 MiB, power 46.78/48.35 W,
temperature 63.48/64.88 C. These counters are sampled approximately once per
second; they are not exclusive renderer CPU or per-process GPU measurements.
Power-plan/clock and driver-cache state were not controlled, so the results
describe this local laptop session rather than a hardware performance rating.

Raw evidence, ignored locally: `runtime/Build/w3-20261016/control/` contains
`summary.json/csv/md`, per-run `run.json`, `result.json`, `bench_frametimes.txt`,
`telemetry.csv`, logs and screenshots, plus immutable binary/seed/harness hashes.
Launch: `runtime/Build/w3-20261016/control.launch.json`; job status exit 0.
Durable compact data: [measurements/20261016-w3-w4.json](measurements/20261016-w3-w4.json).
Method/reproduction: [W3_BENCHMARKS.md](W3_BENCHMARKS.md).

## 2026-10-16: W4 CPU/draw evaluation

Same machine, executable, settings, title scene and frozen warm cache as W3.
Profile first, then separate unprofiled direct-draw off/on runs. This switch
controls the pre-existing consecutive direct-draw fast path; it does not disable
priority-2 commit `9a719c45`. No new runtime optimization was applied.
Results, counter interpretation and remaining acceptance are in
[W4_CPU_DRAWS.md](W4_CPU_DRAWS.md).
Three warm trials per variant gave 54.43 FPS mean off (50.98-58.36) versus
63.95 on (61.14-68.46), a 17.49-percent difference in this title control.
Mean 1-percent low was 28.64 versus 35.59 FPS; mean p99 was 30.522 versus
24.490 ms. All six exited 0 and their screenshots were identical. This supports
keeping the existing fast path locally; representative gameplay and second-PC
acceptance remain open. No new renderer speedup is claimed.
