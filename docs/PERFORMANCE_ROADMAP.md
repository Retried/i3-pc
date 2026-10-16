# i3-pc performance optimization plan

The current merged order of future changes is in
[ROADMAP.md](ROADMAP.md#merged-future-implementation-priorities-2026-10-16).
It combines the remaining scope of priorities 1-7 below with the shadPS4
recommendations; the analysis and numbering below retain their historical meaning.

Analysis date: 2026-10-15. This stage compared proposals with the code, reviewed
the experimental priority-1 patch and planned further validation.
The initial stage did not apply the patch or implement the other priorities.
The later priority-2 implementation is described in the update below;
the comparison table retains the baseline state from before that change.
The plan was also extended with W1-W4 for Windows, AMD Ryzen CPUs and NVIDIA
GPUs. Their numbering is separate from renderer priorities 1-7.

## Basis and status definitions

Current hardware scope (2026-10-16): build, launch and validation targets are
AMD CPUs with NVIDIA Vulkan GPUs only. Historical references below to checking
other GPU vendors do not add them to the current scope. Both benchmark PCs must
use this target hardware; see AGENTS.md and docs/BENCHMARK_PROTOCOL.md.

The original review inspected the local `runtime` submodule checkout pinned to
`81b6211695fe3d1dc1b7712d7e6dcdef2c908275`. `.gitmodules` specified the
`runtime` branch; the checkout had a detached HEAD. The analysis covers that
local code and does not establish alignment with the latest remote branch tip.

- **Implemented**: the mechanism exists in code; this does not establish a benefit.
- **Partially implemented**: parts of the proposal exist, but specific work remains.
- **Experimental**: a patch exists outside the checkout, without full validation.
- **Requires measurements**: a hypothesis about cost or benefit, not a benchmark result.

All benefits in the table below are hypotheses. Data in
[`BENCHMARK.md`](BENCHMARK.md) describes earlier measurements and does not
establish the effectiveness of this patch or the new proposals. Numbers and
observations in code comments are not new benchmarks performed for this analysis.

## Priorities after comparison with the code

| Priority | Proposal and status | Evidence in the reviewed code | Remaining scope and benefit hypothesis | Difficulty / risk |
| --- | --- | --- | --- | --- |
| 1 | Cache bindings and send only changed descriptors: **experimental; requires measurements** | `Pipeline::BindResources` in `vk_pipeline_common.cpp` sends the entire nonempty push-descriptor set; the ordinary descriptor-set path performs `Commit`, `updateDescriptorSets` and binding. `CommandStream::pushDescriptorSetKHR` copies data to the worker without comparing previous values. | Evaluate and validate the supplied patch that eliminates repeated push-descriptor writes. It is not a complete resource-preparation cache. Hypothesis: less CPU work for similar draw calls, potentially higher FPS. | Medium-high: Vulkan state correctness and cache invalidation. |
| 2 | Incremental pipeline state and faster shader-variant selection: **partially implemented; requires measurements** | `GetGraphicsPipeline` caches the previous key/pipeline and has a pipeline map. However, it first calls `RefreshGraphicsKey`, which clears and rebuilds the key. `GetProgram` caches programs, but for an existing program it refreshes data, builds a specialization and then searches `program->modules` linearly. | Measure key rebuilding, specialization and lookup cost before designing updates to dependent fields and a variant index. Hypothesis: less CPU work per draw. | Medium: completeness of register, shader-data and memory dependencies. |
| 3 | Poll the GPU less often and group submits: **partially implemented; requires measurements** | `SubmitPeriodically` in `vk_rasterizer.cpp` already groups work, by default every 512 helper calls (`SOTC_SUBMIT_EVERY`). `Draw` calls `PopPendingOperations`, which calls `work_semaphore.Refresh`. `SubmitExecution` also refreshes the semaphore. Ticks and deferred-operation queues exist. | Measure the number and duration of timeline reads, submits and waits. Consider reducing polling while preserving timely callbacks and guest signals. Hypothesis: lower synchronization overhead. | Medium: readback latency, pacing and GPU starvation with oversized batches. |
| 4 | Remove redundant commands before the worker: **partially implemented; requires measurements** | `Rasterizer::Draw` has `LastDraw`, a change mask and a render-state reuse fast path. The scheduler invalidates tracked dynamic state at a new session. `CommandStream::bindPipeline` still queues every bind. | Inventory emitted binds/dynamic state and existing filters. Priority 1 already covers part of this proposal for push descriptors; do not count its effect twice. Hypothesis: less producer-side copying and fewer worker-side driver calls. | Low-medium; higher for commands that change dependent state. |
| 5 | Precise readback dependencies: **partially implemented; requires measurements and correctness validation** | `BufferCache::DownloadMemory` tracks modified ranges but ends with `scheduler.Finish`. `MirrorToGuest` has asynchronous copies, ticks, a lead limit and changed-word comparisons; some behavior depends on game ID and `I3_*` variables. `DeferLabel` associates some readback with a completion signal. | Describe producer-copy-CPU dependencies, aliasing, CPU overwrites and memory remapping. Do not replace existing waits without proof of equivalence. Hypothesis: stability and possible further reductions in global waits. | High: races, late results and guest-memory corruption. |
| 6 | Prepare pipelines before first use: **implemented for compatible saved caches; partial for the complete proposal; requires measurements** | The `PipelineCache` constructor calls `WarmUp`. `vk_pipeline_serialization.cpp` checks the profile and data versions and restores graphics/compute pipelines from the database. Missing pipelines are still created on use in `GetGraphicsPipeline` / `GetComputePipeline`. | Separately measure empty/warm-cache startup, hits, in-game compilation and startup time. Prewarming new variants requires a separate design. Hypothesis: less stutter and better 1% low. | Medium-high: cache compatibility, memory, startup time and variant coverage. |
| 7 | Batch city-panorama draw calls: **no confirmed implementation of this batching; requires measurements and design** | `CommandStream` exposes indirect commands, and the rasterizer has a consecutive-draw fast path. This does not establish that separate panorama draw calls are combined into one batch. | First establish whether resource state, indices, constants and dependencies permit equivalent semantics. Implementation must be general, without game/shader-specific exceptions, per `runtime/AGENTS.md`. Hypothesis: substantially lower CPU overhead, with no estimated benefit size. | Very high: ordering, barriers, blending, queries and per-draw data. |

Vulkan file paths in the table are relative to
`runtime/src/video_core/renderer_vulkan/`; BufferCache is in
`runtime/src/video_core/buffer_cache/buffer_cache.cpp`.

## Priority-1 patch review (historical)

Superseded on 2026-10-17 by the user's request to integrate roadmap item 8.
The runtime now includes a default-enabled implementation with additional
lifetime invalidation and optional diagnostics. The standalone patch was
removed. See [ROADMAP8_PUSH_DESCRIPTORS_20261017.md](ROADMAP8_PUSH_DESCRIPTORS_20261017.md).
The review below describes the original candidate, not current delivery status.

Input: `priority1-push-descriptor-cache.patch`, supplied separately.
It changes `vk_command_stream.cpp`, `vk_command_stream.h`, `vk_scheduler.cpp`
and `vk_scheduler.h`. `git apply --check --directory=runtime` succeeded on
the checkout described above. This only checks patch applicability: the patch
was not applied, compiled or run. According to its author, it had not passed
a full emulator build or in-game tests.

### Actual scope

- Two independent graphics/compute caches for set 0, with 64 bindings each.
- Comparison of descriptor type and relevant values: buffer/offset/range,
  image view/layout, sampler or texel-buffer view.
- Single descriptors only (`descriptorCount == 1`, `dstArrayElement == 0`),
  without `pNext`, for the types listed in the patch.
- Filtering before copying data to the worker; the entire call is skipped
  when nothing changes. This also applies without the worker.
- Unsupported writes use the existing path and invalidate the cache.
- Disabled by the presence of `SHAD_DISABLE_PUSH_DESCRIPTOR_CACHE` in the
  environment (a value of `0` also disables it).

The patch does **not** skip resource preparation, pipeline selection,
push constants or ordinary descriptor-set updates. It does not reduce draw-call
count or implement the full scope of priority 1.

### Strengths and correctness conditions

Invalidation covers layout changes, target command-buffer changes,
`BeginSession`, ordinary `bindDescriptorSets`, generic `Set` and access through
`Scheduler::CommandBuffer`. Resetting in `BeginSession` is necessary even when
the same command-buffer handle value is reused. Existing write-data copying
before asynchronous replay is preserved; the cache stores values rather than
pointers to user arrays.

Layout-handle comparison is conservative: it forces the supplied set to be
sent again even for compatible layouts. This simplifies correctness at the cost
of possible cache misses.

### Risks and open review items

1. **Cache bypasses and handle lifetime.** `RawCommandBuffer()` does not invalidate
   the cache; the identified callers compare handles. Preserve that contract
   and check direct Vulkan operations and any storage of a handle returned by
   `CommandBuffer()` across later stream operations. Invalidating once when
   obtaining the handle does not protect later writes that bypass the stream.
   Resource/layout handle recycling also requires compatible lifetime management.
2. **Invalidation effectiveness.** Generic `Set` and every `CommandBuffer()`
   invalidate both caches, even for unrelated operations. This is conservative,
   but frequent calls may limit hits. Add measurements of invalidation reasons
   and hit-run lengths.
3. **Coverage.** An entire batch falls back if any write fails the conditions.
   Measure actual descriptor types, binding counts and array writes; do not
   assume most draw calls benefit.
4. **Comparison cost.** Every candidate is checked and then compared. Frequently
   changing resources add CPU cost without eliminating calls. No target-scene
   data establishes the net effect.
5. **State semantics.** Validation must cover partial binding updates,
   graphics/compute switches, layouts and ordinary sets, blit/tile/fault helpers,
   recording restarts, and fallback for `pNext` and large batches.
   Eliminating writes does not replace barriers or resource-content tracking.

Static review conclusion: the scope reduces repeated push-descriptor writes,
and applicability to the sources is confirmed. This does not establish
readiness for implementation, a performance result or full correctness.
At that review date the patch remained an experimental validation candidate.

## Further work order

1. Preserve the baseline commit and identical configuration; prepare a separate
   build with the priority-1 patch. Build the complete emulator and check diagnostics.
2. Validate correctness with the cache enabled/disabled and worker enabled/disabled
   (`SOTC_WORKER_RECORD=0`), covering scene changes, effects, compute, readback,
   long gameplay and command-buffer reuse. Use Vulkan validation layers for
   correctness; measure timing separately without their overhead.
3. Measure priority 1 in repeatable A/B runs. Correctness and CPU-cost results
   determine whether to accept or revise it.
4. Profile priorities 2-4 and establish their cost share, accounting for existing
   optimizations and overlap between 1 and 4. Do not implement them in this stage.
5. Precede priority 5 with a dependency model and correctness analysis.
   For 6, measure existing warmup first. Leave priority 7 as a feasibility study
   after evaluating simpler optimizations.

## Measurement protocol and decision criteria

- Hold constant: commit, patch, build/compiler, hardware, driver, resolution,
  settings, FPS cap, save, camera/route and trial duration. Record all environment
  variables. Measure cold and warm shader caches separately.
- Repeat each configuration at least three times, alternating A/B order.
  Include a heavy panorama, a scene with frequently changing resources and
  a light control scene; compare image correctness and stability too.
- Report frametime distribution, median, p95/p99, average FPS, 1% low and trial
  variability. Define the 1% low calculation and do not mix methods.
- For the patch, measure CPU descriptor preparation/submission time, worker time,
  candidate and changed-write counts, skipped calls, bytes copied to the queue,
  fallbacks and invalidations. Observe GPU time, submits and waits to identify
  shifts in the bottleneck.
- Acceptance requires a full build, no detected correctness/stability regressions,
  a repeatable benefit beyond measurement variability and no significant
  control-scene regression. More cache hits alone do not establish higher FPS.

No builds, game launches or benchmarks were performed during the original
analysis stage. Missing results do not imply zero benefit; the size and cost
of the effect remain unknown.

## Update: priority-2 implementation (2026-10-15)

A separate request implemented the first part of priority 2 in source:

- `PipelineCache::GraphicsState` stores copies of registers affecting the
  render-state portion of the key. Comparison covers all specified fields,
  regardless of the register write path. Unchanged values skip repeated format,
  swizzle and other conversions for that part of the key.
- The pre-shader key and the result of render-target masking are stored
  separately. The latter is reused only when registers and the MRT mask match.
  Stage hashes and vertex-input formats are not reused from an old result;
  they remain current for the draw call.
- `Program::FindPermutation` remembers the previous lookup result for programs
  with multiple variants. It checks specialization and an identical resource
  presence mask. This matters because the existing specialization match ignores
  some resources absent from the query. A changed query uses the existing
  first-matching-variant search; adding or inserting a variant invalidates the result.
- The previous graphics-pipeline cache now belongs to a `PipelineCache`
  instance rather than being global. Removing a pipeline during shader
  replacement still invalidates the pointer.

Shader parameters, SRT memory, specializations and fetch shaders are refreshed
for every draw/dispatch. Correctness does not rely solely on
`change_mask_since_draw`, which does not describe all guest-memory changes.
The disk-cache format and variant-compilation rules were not changed.
Full incremental shader-dependency tracking remains a separate design
possibility. Priorities 1 and 3-7 were not implemented.

Validation of this update:

- Submodule `git diff --check`: no errors.
- Syntax/type checking of the changed `vk_pipeline_cache.cpp`: passed;
  the file was subsequently compiled in the full build.
- Full Windows x64 emulator build, `RelWithDebInfo`, Clang 19.1.5 and MSVC:
  passed, including linking `shadps4.exe` under `runtime/Build/priority2-x64/`.
  Local adjustments selected Python for glslang, a 64-bit Clang process for
  the emulator and fonts, Windows definitions and the full path to the
  64-bit builtins library. These were local build adjustments; project
  configuration files were not changed. The available toolchain differed
  from Clang 23 specified in the repository's `build.bat`.
- No in-game tests or benchmarks were performed. Gameplay correctness,
  CPU savings and FPS effects still require validation.

## Plan extension: Windows / AMD CPU / NVIDIA GPU

Requirements source: the supplied document "i3-pc optimization and development -
Windows / AMD CPU / NVIDIA GPU" (title translated from Polish).
Its scope is recorded below as proposed future work; the request to extend
the documentation did not start implementation.

### Environment and goals

- Windows 10/11 x86-64, AMD Ryzen CPUs and NVIDIA GPUs supporting Vulkan.
  Vulkan support alone does not establish availability of every emulator
  requirement; verify the actual model and driver.
- European inFAMOUS Second Son: CUSA00004, update v1.07.
- Two differently configured PCs. Record CPU/GPU models, memory, OS and drivers
  before measurements; do not assume identical performance bottlenecks.
- Goals: improve average FPS, 1% low and frametime, reduce stutter and improve
  stability while preserving image correctness. These are future evaluation
  criteria, not established effects.

The project is based on `SotC-project/i3-pc`; the working repository is the
`Retried/i3-pc` fork. The priority-2 implementation was published as
`9a719c45` on `runtime`; main-branch commit `887e3e9c` contains the roadmap
and fork submodule URL/pointer. Its successful build is not a target NVIDIA test.

### New stages and original brief-review status

| Stage | Proposed changes | Existing code / files to use | Status and result to validate |
| --- | --- | --- | --- |
| W1 - build and launch automation | Portable tool discovery, building, launching and portable packaging; optional LTO. | `build.bat` and `build-lto.bat` use CMake presets but hardcode Visual Studio Enterprise and LLVM paths. `install.sh` also has local paths. Existing files include `runtime/CMakePresets.json`, `runtime/cmake/CMakeWindowsPresets.json`, `dist/` and `README.md`. | **Partially implemented**: a build process and LTO variant exist. Tool discovery and package completeness/portability require implementation or verification. Result: repeatable builds and launching the same package on a second PC without compilation. |
| W2 - NVIDIA compatibility and diagnostics | Audit Vulkan requirements, shaders, synchronization and readback; add missing diagnostics and justified fallbacks. | `Instance::CollectDeviceParameters` in `vk_instance.cpp` logs vendor, model, driver, Vulkan version and extensions. `GetDriverVersionName` recognizes NVIDIA versions; extension/feature detection, enablement and requirements exist. `vk_pipeline_cache.cpp` also makes driver-dependent profile choices. | **Basic diagnostics implemented; overall stage partial and requires hardware tests**. Avoid duplicate logs. Result: reproducible reports and confirmed target NVIDIA correctness; the original proposal also sought to preserve other GPU paths. |
| W3 - automatic benchmarks and profiling | Standardize results/metadata, A/B comparison and regression detection on both PCs. | `bench.sh` writes CSV and derives FPS/lows from frametimes; retrying a busy environment does not replace independent repeats. Existing tools: `abtest.sh`, `abtest2.sh`, `cityprof.sh`, `tools/perfsample.ps1`, `tools/symprof.py`, `SOTC_PROFILE` and videoout's `bench_frametimes.txt`. Scripts still contain local paths. | **Partially implemented; requires extensions and measurements**. Result: A/B reports with full provenance, cold/warm caches and variability across 3-5 runs of each configuration on each PC. |
| W4 - CPU and draw-call optimization | Select expensive operations from profiles, reduce redundant state/lookups and consider safe caching/batching. | Existing priorities 1-7 cover this scope. `DrawStats`, fast paths in `vk_rasterizer.cpp`, the `vk_command_stream.cpp` worker, synchronization and pipeline caches exist. Priority 2 is implemented and builds, but had no game results at this review. | **Partially implemented; effectiveness requires measurements**. W4 covers existing optimizations rather than duplicating them. Result: a repeatable improvement over baseline, checked on both PCs without image or stability regressions. |

### Specific proposed changes

**W1:** detect Visual Studio Build Tools/MSVC, CMake, Ninja and LLVM; select a
64-bit compiler process and correct target. Check Python, other dependencies
and tool-version compatibility. Resolve paths relative to the repository,
tool installations or explicit parameters. Preserve optional LTO after
checking compiler/linker support. Return clear messages and exit codes.
Portable packages should include required executables, libraries and assets;
document runtime requirements, startup configuration and second-PC launch.
Do not include game data or private user configuration.

**W2:** check required/optional features and initialization in `vk_instance.cpp`
and their use in pipelines, the scheduler and buffer cache. Analyze shader
compilation, synchronization and GPU-to-CPU readback, including vendor/driver
assumptions. Add diagnostics where existing data is insufficient; avoid
per-draw logging. Add fallbacks only for confirmed missing features or errors,
preserving correctness. The original proposal included comparison with other
GPUs; current validation scope is AMD CPUs with NVIDIA GPUs only.
Existing NVIDIA paths alone do not establish complete renderer compatibility.

**W3:** extend existing scripts instead of creating a parallel system.
Keep raw frametimes and available CPU/GPU statistics; mark unavailable data
explicitly. CSV/JSON reports should contain main/runtime commit IDs, dirty
state, build configuration, hardware, OS, driver, emulator settings, scene,
measurement duration, environment variables and shader-cache state.
Automatic comparison should include average FPS, 1% low, frametime distribution
and trial variability; set regression thresholds after collecting a baseline.
Cold/warm caches require separate series of 3-5 runs each.

**W4:** profile draw-call translation, resource preparation, pipeline selection,
descriptors, command recording and synchronization. First evaluate existing
optimizations, including `9a719c45` and the separate push-descriptor patch.
Do not sum overlapping expected benefits. Caching, batching and multithreading
require dependency analysis and preserved rendering semantics. Do not add
aggressive multithreading before profiling or game/shader-specific exceptions.

### Order, stage criteria and manual verification

The original cycle order is **W1 -> W2 -> W3 -> W4**. This does not change
historical priorities 1-7 or the status of recorded implementations.
Before starting W1, audit structure, documentation, build system, profiler
and renderer, and list proposed files/functions. The brief review above is
a starting point, not a complete NVIDIA compatibility audit.

Before each major change, describe the problem, solution, regression risk
and verification. Make small, isolated changes; preserve CUSA00004 v1.07,
project style and existing optimizations until measurements justify replacement.
Use ASCII in new scripts and code comments. A successful build does not
establish gameplay correctness; FPS gains with image/stability regressions
do not meet acceptance criteria.

| Stage | Validation requiring execution / hardware | Completion criterion |
| --- | --- | --- |
| W1 | Build the project and supported LTO variant; package and launch on a second PC without a compiler environment. | Build/package instructions, dependency list and confirmed startup/gameplay trial on the second PC. |
| W2 | Collect logs from both configurations; check rendering, shaders, effects, readback, scene changes and longer gameplay. Separate Vulkan validation from timing. Historical requests to document other-GPU coverage do not expand the current target. | Documented hardware/driver matrix, trial results, no detected regressions in checked coverage and a list of unverified configurations. |
| W3 | Repeat identical scenes/settings 3-5 times on each PC, separately with cold/warm caches; verify raw data and comparisons. | Repeatable A/B report, complete metadata and explicit metric/regression-detection methods. |
| W4 | Compare every optimization against baseline on both PCs; evaluate image correctness, stability, FPS, lows and frametime. | Measured benefit with trial variability and regression checks. Do not claim improvements without data. |

After each stage, report changed files and rationale, reproduction instructions,
checks performed, limitations, risks and proposed follow-up work. For W1,
include build and portable-package instructions. Identify checks requiring
game access, target hardware or a second PC. Do not automatically start
the next stage; each should be independently reviewable and approvable.

Extension status at the time of this entry: **planned work**. This documentation
extension did not change scripts or the renderer and performed no new builds,
benchmarks or in-game tests on target configurations.

## W1 implementation update (2026-10-16)

The W1 row above describes the original planning audit. The wrapper now uses
`tools/build-windows.ps1` for x64 tool discovery and separate normal/LTO builds,
and `tools/package-windows.ps1` for allowlisted ZIP packaging with build metadata,
hashes and dependency inspection. `install.sh` resolves paths from its checkout.
Current validation and usage are tracked in [W1_WINDOWS.md](W1_WINDOWS.md).
Second-PC launch remains required before closing W1. W2-W4 are not started by
this implementation; at that W1 baseline renderer priority 1 was unapplied and no FPS improvement
is claimed.

## W3/W4 local evaluation update (2026-10-16)

Later update, 2026-10-17: priority 1 is integrated by explicit user request as
[roadmap item 8](ROADMAP8_PUSH_DESCRIPTORS_20261017.md), with diagnostic cache
on/off and worker on/off controls. Gameplay correctness and performance
acceptance remain pending; the prior W3/W4 data does not measure this change.

The earlier W3/W4 table records the planning state. Portable Windows capture,
independent cold/warm repeats, provenance, PID-scoped CPU telemetry and explicit
NVIDIA selection are now implemented through the existing benchmark entry points.
One-PC title-control results are in [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md);
reproduction and coverage limits are in [W3_BENCHMARKS.md](W3_BENCHMARKS.md).
Separate CPU profiling and direct-draw off/on evaluation are documented in
[W4_CPU_DRAWS.md](W4_CPU_DRAWS.md). Only opening autosaves and one target PC are
available. These results do not close representative-scene/two-PC acceptance,
isolate priority-2 commit 9a719c45, or validate the unapplied priority-1 patch.
