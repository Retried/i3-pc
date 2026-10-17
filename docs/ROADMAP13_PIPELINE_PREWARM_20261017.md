# Roadmap item 13: missing pipeline variants

## Existing path and baseline evidence

PipelineCache already restores compatible saved graphics/compute pipelines in
WarmUp, with profile, metadata, binary and key version checks. This delivery
keeps that path and content-based shader variant identities. It does not restore
the excluded shader variant shortcut or invent shader resource specializations.

The item-12 Windows x64 Release/LTO build was checked once before editing: exit 0,
expected executable present and SHA-256
`5B153E66AAEFC816FC1E8BE60960DF26551D26F860D2A219BE39C3C3E6322D06`.
That binary was copied into the diagnostic suite before candidate edits.

Windows 11 build 26300, Ryzen 7 5800X3D, NVIDIA RTX 2070 SUPER, driver
32.0.16.1742, CUSA00004 v1.07. Worker 0, SOTC_PROFILE enabled, isolated user/save
copies, empty emulator cache for cold runs, one primer's cache frozen for the
warm run, uncontrolled NVIDIA driver cache, 35-second warm-up and 30-second
measurement window. All three process/telemetry exits were 0, with no matched
critical/device-loss/assertion messages. These are diagnostics, excluded from FPS
comparisons and representative-gameplay acceptance.

| Run | Restored pipelines | Runtime graphics/compute/shader compile log events | First flip |
| --- | --- | --- | --- |
| Cold primer | No preload message on empty-cache path | 295 / 87 / 486 | 3245 ms |
| Cold capture | No preload message on empty-cache path | 295 / 89 / 488 | 3134 ms |
| Warm capture | 382 | 0 / 5 / 5 | 7290 ms |

No compile log events occurred inside any of the final 30-second windows.
Counts are lower bounds because duplicate log suppression is enabled. All five
compute shader hashes compiled on the warm run had no matching program's keyed
binary in the frozen seed. They are missing workload coverage, not evidence that
WarmUp failed to restore those binaries. Exact WarmUp wall time is unavailable
in this baseline: first flip includes the whole startup and cannot substitute
for it. One cold/warm pair cannot establish a startup or FPS regression.

Inspected cold/warm first screenshots both show the opening sideways-controller
gesture prompt. The warm-cache run is not a representative route through Seattle.
No PDB-based attribution or candidate execution is claimed. Raw evidence:
`runtime/Build/roadmap13-20261017/profile-baseline/`; durable conditions, counts,
hashes, first flips and coverage checks:
[measurements/20261017-roadmap13-profile.json](measurements/20261017-roadmap13-profile.json).

## Implemented policy

The shared Vulkan pipeline cache is now created before WarmUp, rather than after
it. Both saved-cache restoration and later creations use the same live cache.
An incomplete cache record cannot leave shader stages/fetch data in the next
record: transient stage arrays are reset per load and after warm-up. Existing
compatibility checks and saved record formats remain unchanged.

New PSO prediction is opt-in with `SHAD_PREWARM_PIPELINE_VARIANTS=1`. Other values
and an absent variable leave it disabled. It is also disabled while shader
collection or shader patching is enabled. The measured control had no missing
graphics pipelines after compatible-cache restoration; enabling speculative
work by default has no measured justification.

After successful compatible restoration, collect at most 128 eligible recipes
and prepare only missing TriangleList/TriangleStrip counterparts. Eligibility
requires ordinary vertex plus fragment stages, no geometry/tessellation/patch
topology, and no serialized multisample pointer dependencies. Keep all shader
variant hashes, vertex formats, render targets, blend state, samples and other
key fields. Existing pipelines are skipped. No compute or new GCN specialization
is guessed: the five uncovered baseline programs require a route that actually
encounters their state.

Recipes own vertex-fetch data because loading later shader permutations can
relocate its original container. Program metadata and Vulkan shader modules
already have PipelineCache lifetime. Construction uses the existing preloading
path and captured host vertex-input/multisample data, without guest reads,
render commands, background mutation or scheduler cache invalidation. A future
draw selects a prepared pipeline only through the normal complete key lookup.
The current repeated-key and shader permutation fast paths remain intact.

At most 32 new PSOs are created, with a 100-ms deadline checked between jobs.
One driver compile can exceed that deadline; it cannot be interrupted. Failed
speculative PSO creation leaves no cached entry; actual first-use creation keeps
its existing error behavior. Temporary recipes are released after prewarming.
Unused prepared PSOs live until PipelineCache destruction, with a bounded count.
Their keys are saved only if the guest later requests them. A prewarm hit then
registers its normal pipeline data and releases the retained serialization data.
No unused predictions are added to persistent cache coverage.

## Measurements and reproduction

`SHAD_PIPELINE_STATS=1` enables cumulative graphics/compute requests, synchronous
PSO and shader compile counts/times, prepared PSOs, actual prewarm hits and
prewarm time. Startup separately reports cache state, restored/stale counts,
existing restoration time and additional preparation time. Reports occur every
4096 pipeline requests and on cache sync/destruction. Shader and PSO timings are
separate nested regions; do not add them to request or frame CPU times. Compile
durations are wall time, not a GPU timing measurement.

`tools/benchmark.py` extracts startup diagnostics, runtime/measurement compile
log event counts and deltas between cumulative snapshots inside measurement.log.
It marks missing counters/timings unavailable and excludes pipeline/GC diagnostic
runs from FPS summaries even without --profile. Python parsing was exercised
against the three real baseline logs. Existing profiling and seed/cache isolation
are reused rather than introducing another harness.

The baseline matrix is
[benchmark-pipeline-profile.json](benchmark-pipeline-profile.json). Candidate
diagnostics with off/on and both worker modes are in
[benchmark-pipeline-prewarm-profile.json](benchmark-pipeline-prewarm-profile.json).
Run the latter against the candidate with `--profile --caches cold warm` and an
isolated seed. Frozen warm caches must come from the same binary/GPU/driver;
do not pass the old baseline suite as the candidate's --warm-seed.

For performance acceptance, use a separately inspected gameplay route, remove
SHAD_PIPELINE_STATS and profiling from all variants, retain only worker/prewarm
off/on controls, and follow BENCHMARK_PROTOCOL with alternating 3-5 trials per
case on both target PCs. Record startup time, restored/new/hit coverage, process
memory, cold/warm cache state and frametimes. A prepared pipeline with no later
hit is extra startup/memory cost, not an avoided compilation. A cold cache has
no recipes, so this mechanism cannot predict unseen shaders on the first run.

## Validation and remaining acceptance

No repository tests were added. Changed-range formatting passed for five modified
C++ source/header files. Nine Windows x64 clang-cl 19.1.5 syntax checks passed
with exit 0 and empty diagnostics; source hashes match the launch. Python/JSON
and PowerShell parsing passed, the benchmark extractor processed the real
baseline logs, and both repositories passed whitespace verification. Source
hashes and detached Release/LTO launch records are under
`runtime/Build/roadmap13-20261017/`. The full Windows x64 Release/LTO build
completed with exit 0; its executable SHA256 is
`B10534C1F7AE6DA1014317A21FB38C904F559D4B0959C3687FC9B1AC79E6DE7C`.
Candidate GPU execution remains a separate check. The syntax worker keeps persistent
logs and status without opening the additional Checking console, as requested;
the full build retains its separate visible log console.

Share these OpenOrbis reference workloads for comparison with the Windows
AMD/NVIDIA candidate; they have not been executed on a console here:

1. Render identical indexed/nonindexed triangle lists and strips with fixed
   vertex/fragment code and resource descriptors. Exercise direct/indirect draws,
   primitive restart, vertex divisors, integer/float vertex formats, clip planes,
   alpha blending, depth and multiple render targets. Compare output/readback
   checksums with prewarm off/on and both worker modes.
2. Change one complete-key field at a time: topology, shader specialization,
   resource layout, attachments, blend masks and sample count. Only the predicted
   topology counterpart with otherwise identical keys may hit. Unsupported
   geometry/tessellation/rect/quad/no-fragment cases must use normal creation.
3. Use empty, complete, incomplete and incompatible caches in directory/archive
   modes. Remove a binary in an isolated cache copy and verify the stale record
   cannot contaminate a later load. Repeat shader patch/collection modes, 128+
   eligible recipes, duplicate counterparts, the 32-PSO/deadline limit and a
   controlled PSO creation failure. Failed predictions must fall back to
   ordinary exact-key creation.
4. Use a route that reaches new compute programs and graphics states before and
   after save/load/scene transitions. Capture exact startup/first-use diagnostics,
   prewarm hits and memory growth; run core/synchronization and GPU-assisted
   validation separately when layers are available.

Candidate measurements, actual prewarm-hit coverage, exact restoration/startup
timing, representative gameplay, Vulkan validation and second-PC/console checks
remain pending. Only one AMD/NVIDIA PC is available. No FPS or stutter reduction
is claimed, and the speculative path remains disabled by default.
