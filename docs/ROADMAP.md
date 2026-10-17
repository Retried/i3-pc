# Priorities

Work only on the requested scope. Delivered W1-W4 implementation work has been
removed from the implementation checklist; its evidence is consolidated in
[W_DELIVERY_20261016.md](W_DELIVERY_20261016.md). W1-W4 are distinct from renderer
priorities 1-7. Complete acceptance is not claimed.

## Remaining release acceptance

- Prepare a replacement second-PC build/package after the rejected attempt
  recorded in HANDOFF, then launch it on a second
  AMD/NVIDIA PC and record gameplay acceptance using [PC2_ACCEPTANCE.md](PC2_ACCEPTANCE.md).
- Supply a Khronos layer for separate core/synchronization and GPU-assisted runs;
  record the release's rendering, save/load/readback and stability checks.
  Only one PC is currently available.
- Complete matching two-PC benchmarks and isolate priority-2 commit `9a719c45`
  with a matching pre-change baseline. Existing title-control A/B does not do this.
  Investigate the documented atomic fallback with hardware reference cases.

These unperformed checks are retained as release acceptance, not marked done
by moving the delivered implementation milestones out of the checklist.
The upstream intake below is future work, separate from the delivered W1-W4
scope and its remaining release acceptance.

## Merged future implementation priorities (2026-10-16)

The order below combines the remaining scope of renderer priorities 1-7 with
the [shadPS4 review](UPSTREAM_SHADPS4_20261016.md). This is the current future
implementation list; numbers 1-7 in PERFORMANCE_ROADMAP are historical identifiers.
Adding an item does not start implementation or establish an FPS improvement.

Build, launch and validation targets: Windows x86-64, AMD Ryzen, NVIDIA Vulkan,
CUSA00004 v1.07. Preserve existing renderer portability paths.
Before each port, compare the recommendation against the current runtime:
the upstream review covers b499ca72, while the later W1-W4 delivery has its own
report. Do not overwrite that work or add completed tasks again.

| Order | Change to implement / evaluate | Dependencies and acceptance criteria |
| --- | --- | --- |
| 1 | Small correctness fixes: rmdir #5373, timed mutex #5386, HTTP header filtering #5330, analog input #5340 + #5377, time/DST #5389. | Separate small ports; take the input pair together. Preserve local mouse, controller and gesture handling; check directory removal, locking and Windows time semantics. |
| 2 | Index buffers: #5278 -> #5327 -> #5358. | One coherent package: index capacity, mapped-range clamping, null address and fallback without requiring maintenance6. Preserve the worker, draw fast paths and argument checks. |
| 3 | Layer and mipmap copies: #5299 -> #5368. | Port both fixes; verify staging capacity, offsets, barriers and local depth/float reuse. |
| 4 | Stencil/depth association and stencil size: #5296. | Port the size correction and AssociateStencil together; check layers, tiling, shadows and depth/stencil copies. |
| 5 | BC texture layout at 2048x2048: #5307. | Update the tables and lookup condition together; check complete mip chains for both BC block sizes. |
| 6 | Shader correctness: first vertex/instance IDs in indirect draws #5348, then CLAMP/LEGACY #5346 and fp64 detection #5342. Conditional: gather #5344, U64 #5366 and descriptor pattern #5352. | Preserve local NaN behavior, specializations and variant caches. Version incompatible cache data; #5352 requires a serialization audit. Promote conditional additions when confirmed in game shaders/logs. |
| 7 | VFS path normalization and mount matching: #5207. | Check save/load, overlays and mount boundaries; avoid unnecessary changes to portable paths. |
| 8 | Push descriptor cache, historical priority 1: integrated runtime implementation, enabled by default. | Validate invalidation, new-port compatibility and gameplay; run same-binary cache on/off A/B with and without the worker. No standalone patch is required. |
| 9 | Reduce GPU polling and group submits, remaining scope of priority 3. | Profile timeline reads, submits and waits first; preserve timely readback, callbacks and guest signals. |
| 10 | Eliminate redundant commands before the worker, remaining scope of priority 4. | Inventory existing filters and measure producer/worker cost. Do not count the descriptor-cache effect from item 8 twice. |
| 11 | Precise readback dependencies, remaining scope of priority 5; separate CMask port #5046. | Start with a producer-copy-CPU model, aliasing, remapping and CPU overwrites. Port CMask separately with owner ID/UID and clear-state checks; do not remove waits without proof of equivalence. |
| 12 | GC/readback redesign #3396 as a separate project. | Follow the analysis of item 11 and its CMask interactions. Preserve slot pressure, deferred destruction and local mirrors; require long memory-pressure runs and protection against stale writes to guest memory. No wholesale merge. |
| 13 | Prewarm missing pipeline variants, remaining scope of priority 6. | Measure existing WarmUp and in-game compilation, separately for cold/warm caches. Do not reimplement restoration from an existing compatible cache. |
| 14 | General draw-call batching, historical priority 7. | Follow profiling of simpler changes and a design for state, barrier, blending and per-draw data dependencies. No game/shader-specific exceptions. |
| 15 | Conditional API/HLE additions and minor improvements from the upstream matrix. | Add only with evidence of a missing call or a specific CUSA00004 v1.07 issue. Includes GNM, guest pthread/POSIX, I/O events, temporary mounts and sign-in; networking, music, USB, UI and configuration have lower priority. |

Item 1 is implemented in the local working tree. Port boundaries, Windows
time adaptation, validation and pending OpenOrbis/gameplay checks are in
[ROADMAP1_CORRECTNESS_20261016.md](ROADMAP1_CORRECTNESS_20261016.md).
Do not schedule its implementation again; build/runtime acceptance remains
separate from source completion.

Item 2 is also implemented locally as one index-buffer package. Integration,
validation and pending hardware acceptance are in
[ROADMAP2_INDEX_BUFFERS_20261016.md](ROADMAP2_INDEX_BUFFERS_20261016.md).
Do not schedule these source ports again; the full build and runtime checks
remain distinct from implementation.

Item 3 is implemented locally as the layer/mipmap copy package. Staging capacity,
format/plane accounting, synchronization and pending validation are documented
in [ROADMAP3_IMAGE_COPIES_20261016.md](ROADMAP3_IMAGE_COPIES_20261016.md).
Do not schedule these source ports again; runtime acceptance remains pending.

Item 4 is implemented locally: stencil footprint correction and shared depth
association, including copy destinations. Integration and pending validation
are in [ROADMAP4_STENCIL_20261016.md](ROADMAP4_STENCIL_20261016.md).
Do not schedule this source port again; build/runtime acceptance is separate.

Item 5 is implemented locally: BC layout tables and their lookup guard now cover
2048x2048 complete mip chains. Compiler-evaluated layout checks and pending
hardware acceptance are in [ROADMAP5_BC_LAYOUT_20261016.md](ROADMAP5_BC_LAYOUT_20261016.md).
Do not schedule this source port again; build/runtime acceptance is separate.

Item 6's required shader ports (#5348, #5346 and #5342) are implemented locally,
with local NaN handling and versioned shader metadata/binaries. Cache integration,
validation and the evidence-gated conditional additions are documented in
[ROADMAP6_SHADERS_20261016.md](ROADMAP6_SHADERS_20261016.md).
Do not schedule the required source ports again; conditional ports and runtime
acceptance remain separate.

Item 7 is implemented locally: shared guest-path normalization, mount replacement
and matching, virtual root access and directory-path ownership. Windows adaptation,
validation and pending save/load/overlay acceptance are documented in
[ROADMAP7_VFS_20261017.md](ROADMAP7_VFS_20261017.md).
Do not schedule this source port again; runtime acceptance remains separate.

Item 8 is implemented directly in the runtime and enabled by default, following
the user's integration request. The standalone experimental patch was removed.
Invalidation, fallback paths, diagnostics and pending correctness/performance
acceptance are in [ROADMAP8_PUSH_DESCRIPTORS_20261017.md](ROADMAP8_PUSH_DESCRIPTORS_20261017.md).
Do not schedule this source integration again or infer an FPS gain from it.

Renderer priority 2 is already implemented: the matching baseline, validation
and measurements listed under release acceptance remain, without requesting
implementation again. Do not remove existing optimizations without evidence.

Item 9 is implemented locally with redundant timeline-read removal, monotonic
single-read refresh publication, submission-relative periodic grouping and
optional exact synchronization counters. The initial diagnostic profile has
scene/symbol limits; full counter profiling and correctness/performance
acceptance remain pending. Scope, controls and evidence are in
[ROADMAP9_GPU_SUBMISSIONS_20261017.md](ROADMAP9_GPU_SUBMISSIONS_20261017.md).
Do not schedule these source changes again or infer an FPS gain from them.

Item 10 is implemented locally: producer-side filtering of repeated pipeline,
index/legacy-vertex bindings and push constants, with independent diagnostics,
invalidation and cache off/on controls. Existing dynamic-state, render-scope and
descriptor filters remain intact. Exact candidate producer/worker cost,
Vulkan/gameplay correctness and performance acceptance remain pending; see
[ROADMAP10_COMMAND_FILTERING_20261017.md](ROADMAP10_COMMAND_FILTERING_20261017.md).
Do not reimplement these filters or count item-8 descriptor savings again.

Item 11 is implemented locally as a readback dependency/lifetime package and a
separate CMask #5046 port. Mapping generations, conditional expected-byte commits
and mirror reservations protect replacement mappings, observed CPU changes and
copy-to-CPU lifetimes. Existing waits remain; unknown asynchronous dependencies
fall back synchronously. Model, limits and pending reference/runtime acceptance:
[ROADMAP11_READBACK_20261017.md](ROADMAP11_READBACK_20261017.md) and
[ROADMAP11_CMASK_20261017.md](ROADMAP11_CMASK_20261017.md).
Do not repeat these source changes or treat them as completion of item 12.

Item 12 is implemented locally as a focused GC/readback redesign derived from
#3396: synchronous producer-side image commits, complete mip/layer tiling with
padding preservation, conservative buffer/alias ownership, actual live allocation
accounting and bounded collection with the local slot-pressure trigger intact.
Deferred destruction, local mirrors and item-11 CMask ownership remain. Full
build and long memory-pressure/runtime acceptance are separate; scope, deliberate
upstream differences and pending OpenOrbis workloads are in
[ROADMAP12_GC_READBACK_20261017.md](ROADMAP12_GC_READBACK_20261017.md).
Do not infer stability, pressure recovery or an FPS improvement from compilation.

Item 13 has a local bounded, opt-in PSO prewarmer and pipeline diagnostics;
existing compatible-cache restoration is retained. Cold/warm baseline profiling
found no missing graphics pipelines in the opening control after restoration,
so speculative TriangleList/TriangleStrip counterparts remain disabled by default
(`SHAD_PREWARM_PIPELINE_VARIANTS=1` enables evaluation). Candidate hit coverage,
exact startup timing and representative gameplay/performance acceptance remain
pending. Scope and measurements:
[ROADMAP13_PIPELINE_PREWARM_20261017.md](ROADMAP13_PIPELINE_PREWARM_20261017.md).

#5316 has a local equivalent. #5317 needs at most a separate comparison of
page-protection and error-handling details, rather than another complete port.
POSIX/macOS/Rosetta host changes, release markers and upstream AGENTS.md do not
enter this target's implementation queue. Do not restore previously excluded
deferred uploads or the shader-variant shortcut.

Full port rationale, SHAs and PR links are in
[UPSTREAM_SHADPS4_20261016.md](UPSTREAM_SHADPS4_20261016.md); technical details of
the historical priorities are in [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md).
Implement small packages with separate correctness validation and measurements
following BENCHMARK_PROTOCOL. Pending execution state is in [HANDOFF.md](HANDOFF.md).
