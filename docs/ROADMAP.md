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
| 8 | Push descriptor cache, historical priority 1: evaluate and potentially implement the experimental patch. | Validate invalidation and compatibility with new ports first, then run A/B with and without the worker. The existing patch remains unapplied. |
| 9 | Reduce GPU polling and group submits, remaining scope of priority 3. | Profile timeline reads, submits and waits first; preserve timely readback, callbacks and guest signals. |
| 10 | Eliminate redundant commands before the worker, remaining scope of priority 4. | Inventory existing filters and measure producer/worker cost. Do not count the descriptor-cache effect from item 8 twice. |
| 11 | Precise readback dependencies, remaining scope of priority 5; separate CMask port #5046. | Start with a producer-copy-CPU model, aliasing, remapping and CPU overwrites. Port CMask separately with owner ID/UID and clear-state checks; do not remove waits without proof of equivalence. |
| 12 | GC/readback redesign #3396 as a separate project. | Follow the analysis of item 11 and its CMask interactions. Preserve slot pressure, deferred destruction and local mirrors; require long memory-pressure runs and protection against stale writes to guest memory. No wholesale merge. |
| 13 | Prewarm missing pipeline variants, remaining scope of priority 6. | Measure existing WarmUp and in-game compilation, separately for cold/warm caches. Do not reimplement restoration from an existing compatible cache. |
| 14 | General draw-call batching, historical priority 7. | Follow profiling of simpler changes and a design for state, barrier, blending and per-draw data dependencies. No game/shader-specific exceptions. |
| 15 | Conditional API/HLE additions and minor improvements from the upstream matrix. | Add only with evidence of a missing call or a specific CUSA00004 v1.07 issue. Includes GNM, guest pthread/POSIX, I/O events, temporary mounts and sign-in; networking, music, USB, UI and configuration have lower priority. |

Renderer priority 2 is already implemented: the matching baseline, validation
and measurements listed under release acceptance remain, without requesting
implementation again. Do not remove existing optimizations without evidence.

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
