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

## 2026-10-17: item-9 pre-change diagnostic profile

Ryzen 7 5800X3D / NVIDIA RTX 2070 SUPER, Windows 11 build 26300, driver
32.0.16.1742; one PC. Preserved Release/LTO executable SHA-256
`5454EF744091890C7DCB59ED3166369ADF3D27A4D8711C4AC96F8E2C7966EC2C`,
SOTC_PROFILE enabled, empty emulator cache, uncontrolled driver cache,
35-second warm-up and 30-second capture. Process/telemetry exit 0.

Screenshot review rejected the requested title-control label: the seed enters
the opening cinematic/sideways-controller gesture prompt. This is diagnostic
only, excluded from FPS comparisons. Nine approximately three-second windows
report 0 ms stream/fault waits and 0-1 ms Scheduler::Wait (rounded inclusive
totals). Exact timeline-read/queue-submit counts and durations are unavailable;
the legacy submits field is a frame counter. Export-only symbolization without
a matching PDB was rejected. No before/after speedup is measured or claimed.

Raw evidence: `runtime/Build/roadmap9-20261017/profile-baseline/`. Durable
provenance/windows: [measurements/20261017-roadmap9-profile.json](measurements/20261017-roadmap9-profile.json).
Implementation, exact-counter controls and pending matching acceptance:
[ROADMAP9_GPU_SUBMISSIONS_20261017.md](ROADMAP9_GPU_SUBMISSIONS_20261017.md).

## 2026-10-17: item-10 command-stream baseline diagnostics

Successful item-9 Windows x64 Release/LTO binary SHA-256
`CB2F8823595A86D823A311DC4FB46B0B97DC32DCEFE5B35D055AAE64DC46E296`,
Ryzen 7 5800X3D / NVIDIA RTX 2070 SUPER, Windows 11 build 26300 and driver
32.0.16.1742. One profiled process per worker mode, isolated identical seed,
empty emulator caches, uncontrolled driver cache, 35-second warm-up and
30-second capture. Both modes still use the old command stream; item-10 source
edits present at capture were not part of the executed binary. Both process
and telemetry exits were 0; no matched critical/device-loss/assertion messages.

Four 1920x1080 screenshots were inspected and show the opening sideways-controller
gesture prompt without an evident difference. This is a seed-dependent control,
not representative gameplay or target-game acceptance. Ten approximately
three-second render-thread CPU windows per mode range from 391 to 1422 ms
(worker off) and 500 to 1422 ms (worker on). The old direct-stage times overlap;
process CPU minus render-thread CPU is not worker CPU. Exact worker replay and
per-filter producer cost are unavailable in this binary. No PDB attribution,
unprofiled A/B result or item-10 FPS/CPU gain is claimed.

Raw evidence: `runtime/Build/roadmap10-20261017/profile-baseline/`. Durable
conditions, CPU/stage windows and hashes:
[measurements/20261017-roadmap10-profile.json](measurements/20261017-roadmap10-profile.json).
The new optional counters and matched four-variant matrices enable candidate
cost measurement after its build; acceptance remains pending as described in
[ROADMAP10_COMMAND_FILTERING_20261017.md](ROADMAP10_COMMAND_FILTERING_20261017.md).

## 2026-10-17: item-12 validation boundary

The item-11 Windows AMD/NVIDIA Release/LTO baseline completed with exit 0 and
verified executable SHA-256
`C84F07B10843E58575DE8913D19211E0D30271DC54162EC7F577F9E21AE96BA7`.
Item 12 changes GC/readback synchronization and allocation accounting. No candidate
runtime timing, FPS gain, memory-pressure recovery or long-run stability result is
claimed. SHAD_GC_STATS diagnostics and compilation are not timing measurements.
Required 45-minute worker-off/on pressure/reference runs and conditions are in
[ROADMAP12_GC_READBACK_20261017.md](ROADMAP12_GC_READBACK_20261017.md).

## 2026-10-17: item-13 cold/warm pipeline diagnostics

Item-12 Release/LTO binary SHA-256
`5B153E66AAEFC816FC1E8BE60960DF26551D26F860D2A219BE39C3C3E6322D06`,
Ryzen 7 5800X3D / RTX 2070 SUPER, Windows 11 build 26300, driver 32.0.16.1742,
CUSA00004 v1.07, worker 0, SOTC_PROFILE enabled. Isolated identical seed,
35-second warm-up plus 30-second capture, empty emulator cache versus frozen
same-binary primer cache; uncontrolled NVIDIA driver cache. Three processes
(primer, cold, warm) and telemetry exited 0 with no matched critical/device-loss/
assertion messages. Inspected cold/warm first screenshots show the opening
sideways-controller gesture prompt. These profiled diagnostics are excluded from
FPS comparisons; no candidate gain or representative gameplay acceptance.

Cold capture logged at least 295 graphics, 89 compute and 488 shader compilations.
Warm capture restored 382 pipelines and logged 0 graphics, 5 compute and 5 shader
compilations; the five compute program hashes had no keyed binaries in the seed.
No compile log events occurred in the final 30-second windows. First flip was
3134 ms cold versus 7290 ms warm (primer 3245 ms). This is whole startup, not
WarmUp duration; one pair and profiling cannot establish a performance change.
Exact restoration timing is unavailable in the baseline and is now instrumented.

Raw evidence: `runtime/Build/roadmap13-20261017/profile-baseline/`. Durable
conditions/counts/hashes: [measurements/20261017-roadmap13-profile.json](measurements/20261017-roadmap13-profile.json).
Policy, opt-in prewarm controls and pending candidate/two-PC acceptance:
[ROADMAP13_PIPELINE_PREWARM_20261017.md](ROADMAP13_PIPELINE_PREWARM_20261017.md).
