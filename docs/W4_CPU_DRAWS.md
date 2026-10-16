# W4: local CPU and direct-draw evaluation (2026-10-16)

This is a partial local evaluation on the one available AMD/NVIDIA PC.
Build/machine/settings provenance is in [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md).
The available workload is the static title/Continue control, not a city panorama,
resource-churn scene or combat. No new C++ optimization is accepted from it.

## Profile collected before A/B

The separate SOTC_PROFILE run exited 0 and confirmed NVIDIA/APP_VER 01.07.
The latest complete sampler interval near the measurement end contained 5930
samples; 2449 (41.3 percent) had the actual instruction outside the executable.
ASLR was resolved using image load base 0x700000000000 and the matching PDB;
no nearest executable frame was unknown. The sampler resets every ten seconds;
the reported histogram is one approximately ten-second interval, not the entire
30-second capture. Stack scanning is approximate and can include stale stack
addresses. A nearest executable frame is not necessarily the executing leaf.

| Nearest executable frame | Samples | Percent |
| --- | --- | --- |
| MemoryManager::CopySparseMemory | 593 | 10.0 |
| Semaphore::Refresh | 472 | 8.0 |
| Liverpool::ProcessGraphics | 397 | 6.7 |
| CommandStream::Drain | 380 | 6.4 |
| BufferCache::ObtainBuffer | 281 | 4.7 |

The profile suggests memory/resource handling and semaphore/command processing
deserve representative-scene investigation. It does not prove an exclusive
breakdown or justify weakening synchronization, memory protection or readbacks.
Existing resource/pipeline/bind/command timing counters overlap and must not be
added into an exclusive CPU total. Profile-run FPS are excluded from comparisons.

Raw evidence: `runtime/Build/w4-20261016/profile/`, including `symbols.json`,
`title-control-warm-baseline-1/profile-after.txt`, `measurement.log`, logs,
telemetry, binary/PDB and harness snapshots. The sampler histogram files were
preserved; an initially attempted cumulative subtraction was rejected because
the runtime actually resets counts. The symbolizer now handles one interval.
Reproduction is documented in [W3_BENCHMARKS.md](W3_BENCHMARKS.md).

## Existing direct-draw fast path

The unprofiled A/B uses one binary and the same immutable emulator warm cache,
three independent processes per variant, in order off/on, on/off, off/on.
Off sets I3_NO_DRAW_FASTPATH=1; on leaves it unset. The matrix is
`docs/benchmark-fastpath-control.json`. Raw series and launch records are under
`runtime/Build/w4-20261016/fastpath/` and `fastpath.launch.json` respectively.
The first detached launch disappeared before creating a suite, with no final
status; it is recorded as interrupted/unknown and contributes no measurements.

| Fast path | N | Average FPS mean (range) | 1% low mean | Median ms mean | p95 ms mean | p99 ms mean | Worst ms max |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Off | 3 | 54.43 (50.98-58.36) | 28.64 | 16.922 | 25.115 | 30.522 | 111.113 |
| On | 3 | 63.95 (61.14-68.46) | 35.59 | 14.143 | 21.264 | 24.490 | 55.512 |

On/off mean FPS differed by 17.49 percent. The largest observed within-variant
FPS range was 13.57 percent of that variant's mean. The difference clears this
descriptive local noise check, with only three trials per variant; it is not a
statistical significance test or a gameplay speedup claim. Both variants retain
priority-2 changes. All six runs exited 0, confirmed NVIDIA/APP_VER 01.07 and had
no matched critical/device-loss/assertion message. Fast-draw counters were zero
in every off interval; on-run means were approximately 192640, 166553 and 176908
per three-second interval. The switch therefore exercised the intended path.

All twelve A/B start/end screenshots and both profile screenshots were reviewed.
They match the W3 control image exactly after RGB decoding at 1920x1080. This
checks only the static title; transition/effect correctness remains unverified.
No slow-frame outliers were removed, including the 111.113 ms off frame.
The evidence supports retaining the existing fast path for this control workload.
It does not establish the benefit of any newly implemented optimization.

Per-run metrics, hashes, counters, telemetry and provenance are preserved in
[measurements/20261016-w3-w4.json](measurements/20261016-w3-w4.json). The comparison
command was exercised on the two local suites: it correctly reports one distinct
machine, no two-PC coverage and null for missing cases.

## Decision and remaining scope

Keep existing renderer optimizations. Priority-2 `9a719c45` needs a separate
matching pre-change build because this runtime has no switch isolating that
cache. At this report's baseline the priority-1 patch passed the applicability
check but remained unapplied. It is now integrated as
[roadmap item 8](ROADMAP8_PUSH_DESCRIPTORS_20261017.md), with runtime acceptance pending.
It filters descriptor writes rather than eliminating resource preparation or
combining draws; the measured fast-path comparison cannot establish its benefit.

Full W4 acceptance requires city/resource-churn/control scenes, visual and
stability checks, separate Vulkan validation and 3-5 matching trials on a second
AMD/NVIDIA PC. GPU frame times, detailed lock/driver waits and full gameplay
correctness remain unmeasured. The unavailable Khronos layer prevents claiming
validation-clean rendering. No batching, new cache or synchronization relaxation
was introduced without that evidence.
