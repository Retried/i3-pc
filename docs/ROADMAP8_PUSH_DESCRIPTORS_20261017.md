# Roadmap item 8: integrated push-descriptor cache

## Delivery and scope

The user requested direct integration rather than a separately applied
experimental patch. Push-descriptor filtering is now part of the runtime's
normal CommandStream path and enabled by default. The standalone patch was
removed from docs/patches; builds require no patch application step.

Runtime base: `f88d3b6f331272ce854bda5875c11386b180f94f`, with local items 1-7
retained. The original candidate is retained only as local build evidence in
`runtime/Build/roadmap8-20261017/original-priority1.patch`; the source changes
include additional lifetime handling and diagnostics beyond that candidate.
This implements descriptor-write filtering, not a resource-preparation cache
or draw batching. Runtime/performance acceptance remains distinct from integration.

## Cache behavior

- Separate graphics and compute state for set 0, with 64 binding slots each.
  State belongs to the recording producer, not the worker thread.
- Cache values are descriptor type plus the fields relevant to that type:
  sampler, combined sampler/view/layout, view/layout, buffer/offset/range or
  texel-buffer view. No caller-owned payload pointer is retained in the cache.
- Only single descriptors at array element zero, without pNext, with supported
  types and non-null required payloads are candidates. A nonempty batch must
  fit the fixed comparison/scratch arrays and every binding must fit the cache.
- Changed writes retain their original order and are forwarded; unchanged
  writes are omitted. Entire unchanged calls return before copying/queueing.
  Partial updates and repeated writes to the same binding update state in order.
- Unsupported types, arrays, nonzero array elements/sets, large batches,
  extension chains and empty batches use the complete original path and
  invalidate tracked state. Chained/oversized asynchronous payloads still
  drain and record in place, preserving their original lifetime/ordering rules.
- Both worker recording and synchronous recording use the same filter. The
  existing deep copy of forwarded writes and image/buffer/texel arrays remains.
  Resource preparation, push constants, ordinary sets, barriers and draw counts
  are unchanged. Resource-content changes alone do not require descriptor
  rebinding; synchronization and access tracking still run independently.

Incremental push updates and separate pipeline bind points follow
[Khronos descriptor-set semantics](https://docs.vulkan.org/spec/latest/chapters/descriptorsets.html).
Layout comparison deliberately uses exact handle equality rather than trying
to prove compatibility between different layouts.

## Invalidation and lifetime audit

| Event | Handling |
| --- | --- |
| New recording session | BeginSession invalidates unconditionally, including reuse of the same command-buffer handle. |
| Target handle change | SetTarget invalidates before selecting another target; its existing drain contract remains. |
| Layout change at a bind point | Invalidate all binding slots at that bind point before considering new writes; the other bind point remains independent. |
| Ordinary descriptor-set binding | Invalidate both caches before queueing bindDescriptorSets, conservatively covering layout/set disturbance. |
| Generic stream Set callback | Invalidate both caches before the opaque callback can record commands. Named dynamic-state and push-constant wrappers retain their semantics. |
| Direct command-buffer access | Scheduler::CommandBuffer drains and invalidates before returning the handle. Its contract now explicitly forbids retaining that handle across Stream calls. |
| Deferred resource reclamation | Completed ordinary pending callbacks publish an atomic resource-change notice. Before its next push, the producer consumes the notice and invalidates cache values. This covers deferred image/view destruction and handle reuse without modifying producer cache arrays from another thread. |
| Shader replacement | ReplaceShader invalidates before destroying/replacing pipelines and their layouts, covering layout-handle reuse within a recording session. |
| Unsupported push batch | Invalidate and forward the original batch, allowing a later supported batch to rebuild state. |

RawCommandBuffer remains comparison-only; the three repeated-indirect callers
only compare/store handles and issue commands through the stream. Blit, tile
and fault-processing helpers obtain direct command buffers through CommandBuffer
before issuing their descriptor writes. Present/FSR/postprocess paths use the
presenter's direct-access recording path; no raw-handle bypass was added.
These helpers retain their pre-existing command ordering and resource barriers.

Normal deferred callbacks can reclaim image views; priority callbacks retain
their separate readback/staging-allocation behavior and do not modify cache
arrays. Notifications are coalesced until the next producer push. This does not
replace Vulkan's existing resource lifetime or command-buffer synchronization
requirements. No persistent shader, specialization or pipeline-key layout is
changed, so item 6's cache versions and content-based variant names remain intact.

## Diagnostics and A/B controls

- Default: cache enabled, statistics disabled.
- Presence of SHAD_DISABLE_PUSH_DESCRIPTOR_CACHE disables filtering for the
  process, including when its value is `0`. This is a same-binary diagnostic
  control, not a separate build or experimental patch mode.
- Presence of SHAD_PUSH_DESCRIPTOR_STATS enables cumulative per-stream counters.
  Session completion logs them at most once per three seconds. They report
  calls, cacheable calls, input/forwarded writes, skipped calls, layout changes,
  longest per-bind-point unchanged-call run and invalidation requests by reason.
  Requests are counted even if that cache was already invalid; layout changes
  have their own counter, including first use after invalidation. Counters do
  not reset between reports.
- SOTC_WORKER_RECORD=0 selects synchronous recording; unset/default selects the
  worker. The two cache modes can be compared with each worker mode.

Use diagnostic counters to establish coverage and invalidation frequency;
input writes minus forwarded writes includes omissions from partial batches.
They do not establish an FPS improvement. Disable optional statistics for timing
trials and keep all other configuration and shader-cache state matched.

## Validation and build records

- Follow-up at publication: the full build completed with exit 0. SHA-256:
  `3F25A8F008C39BEECF7E986A6E727D63D399D3F9EE1DE9C966C2F981667F3565`.
  The executable was subsequently preserved and verified at
  `runtime/Build/xbox-20261017/previous-executable.exe` before independent Xbox
  work reused the build directory. This does not validate that later work.

- Previous item-7 Windows x64 Release/LTO build completed with exit 0; executable
  present and SHA-256 verified:
  `EA55565AEE549B0C5CAF111C0657B03688F10EC0017608C928C4CE571D5054D4`.
  Its output directory is preserved as the pre-item-8 baseline.
- Nine Windows x64 clang-cl syntax checks passed with exit 0: command stream,
  scheduler, pipeline cache, pipeline common, rasterizer, runtime, tile manager,
  blit helper and fault manager. Final diagnostic logs are empty. Changed-range
  clang-format and whitespace checks passed. Earlier local changes are retained.
- Evidence: `runtime/Build/roadmap8-20261017/`, including syntax-launch.json,
  syntax-status.json, per-file response files/logs, format-status.json and
  item8.diff. No repository tests were added, following runtime/AGENTS.md.
- Full Windows x64 Release/LTO launch record: build-launch.json, with source
  SHA/dirty/file-hash snapshot, persistent stdout/stderr and build-status.json.
  Expected executable:
  `runtime/Build/roadmap8-x64-Clang-Release-lto/shadps4.exe`.
  Separate native consoles are recorded in syntax-console-launch.json and
  console-launch.json; no desktop input or activation automation is used.
- No GPU execution, Vulkan layer, gameplay, readback-hash or benchmark result
  is claimed by the source/syntax checks. Implementation is integrated; runtime
  and performance acceptance is pending. No FPS claim is made.

## Pending correctness and performance acceptance

Share an OpenOrbis sample that alternates buffer, sampled/storage image,
sampler and texel-buffer inputs while writing deterministic readback hashes.
Record descriptors and output hashes on console and Windows AMD/NVIDIA.

1. With cache on/off and worker on/off, compare identical full writes, one-field
   changes, partial writes and repeated binding writes; vary buffer offset/range,
   image layout/view and sampler independently. Include draw/dispatch alternation.
2. Exercise layout switches, ordinary sets, generic/direct helper commands,
   blits, tiling, faults, new command buffers and reused command-buffer handles.
   Check the first write after each invalidation is forwarded.
3. Exercise arrays, pNext, unsupported types, bindings 63/64, sets above zero,
   empty writes and batches above capacity, then return to supported writes.
   Run Vulkan core/synchronization validation separately from GPU-assisted mode.
4. Destroy/recreate eligible resources after their legal completion points,
   recycle image/view handles, replace a shader and rebuild its pipeline.
   Check resource/layout invalidation and stable output hashes.
5. In CUSA00004 v1.07 compare transitions, lighting/shadows, particles/effects,
   save/load, depth/float reuse, BC mip chains and indirect shader variants from
   recent ports; include extended resource churn and readbacks.
6. Follow BENCHMARK_PROTOCOL.md: matched panorama, resource-churn and control
   scenes, 3-5 alternating cache on/off trials in each worker mode, on two
   AMD/NVIDIA PCs. Record raw frametimes, CPU cost, coverage counters and image
   comparisons in PERFORMANCE_LOG.md. Only one target PC is currently available;
   the second-PC and Khronos-layer prerequisites remain recorded in HANDOFF.

The earlier direct-draw fast-path measurements do not isolate this cache, and
its effect must not also be credited to future roadmap item 10.
