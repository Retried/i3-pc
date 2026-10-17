# Roadmap item 10: redundant commands before worker recording

## Delivery and inventory

The runtime now filters unchanged pipeline/index/legacy-vertex bindings and
identical push-constant updates on the recording producer, before Reserve,
auxiliary-data copies or Push. It applies to synchronous and worker recording.
Filtering is enabled by default with a same-binary disable control. This does
not batch draws, remove synchronization or change resource preparation.
Correctness and performance acceptance remain separate from source completion.
No FPS improvement is claimed.

Runtime HEAD remains `ace6fae75337d8cd192f846fe5ece548ea7836e8`, with the local
item-9 source changes retained. The pre-item-10 binary is the successful item-9
Windows x64 Release/LTO build, SHA-256
`CB2F8823595A86D823A311DC4FB46B0B97DC32DCEFE5B35D055AAE64DC46E296`.
Its executable, metadata and before-source snapshots are preserved under
`runtime/Build/roadmap10-20261017/`. The full build's source state includes both
items; it must not be described as an isolated item-10 build from clean HEAD.

The code inventory found these filters already in place:

| Existing mechanism | Boundary retained |
| --- | --- |
| Rasterizer::LastDraw and change mask | Reuse eligible render targets/state between consecutive direct draws; still prepare current resources, vertices and indices. |
| DynamicState setters and Commit | Compare individual state values, emit dirty fields and invalidate at a new session. Item 10 does not add a second value cache for these commands. |
| Scheduler::BeginRendering | Reuse an identical active rendering scope. Begin/end rendering commands are retained when scopes change. |
| PipelineCache | Cache pipeline selection and shader variants; this is distinct from eliminating repeated Vulkan pipeline binds. |
| Item-8 push-descriptor cache | Compare descriptor values and suppress unchanged writes before queue copies; leave its cache control/counters independent. |
| CommandStream | Preserve deep copies, FIFO chunk replay, direct fallback drains and the synchronous recording path. The old wrappers forwarded binds and push constants unconditionally. |
| Item-9 scheduler | Preserve periodic submission grouping, polling conditions, waits and guest completion handling. |

## Filter keys and fallback

| Command | Comparison and scope |
| --- | --- |
| bindPipeline | Separate graphics/compute handles. Skip an identical non-null pipeline at the same bind point only while that tracked binding remains valid. Unsupported bind points/null pipeline use the original path and invalidate tracked command state. |
| bindIndexBuffer / bindIndexBuffer2KHR | Buffer, offset, index type, size and API variant. Changing between sized and legacy bindings always forwards, even with the same buffer/offset. Null bindings remain distinct from invalid cache state and keep their original feature-dependent meaning. |
| bindVertexBuffers | The entire most recent first/count/buffer/offset tuple, up to 32 bindings within slots 0-31. No partial-write elision. A different range, including overlapping partial ranges, replaces the last-call snapshot. Empty/oversized/unsupported tuples forward and invalidate that snapshot. |
| bindVertexBuffers2 | Always forward, including size/stride values. Invalidate the legacy vertex tuple because sized binding changes cannot be inferred from a later legacy bind. This command also invalidates the graphics-pipeline cache conservatively. |
| pushConstants | Exact layout handle, stage mask, offset, payload size and payload bytes, up to 128 bytes, with nonempty aligned updates and valid payload pointers. Track only the most recent whole call across all stages; differing/overlapping partial writes replace the snapshot, so a later full update forwards. Larger/unsupported updates forward and invalidate the snapshot. |

All cached arrays contain values rather than caller-owned pointers. A forwarded
command retains the existing worker deep copy. Bitwise push-constant comparison
preserves float/NaN bit patterns. Resource contents may change without requiring
a binding command: resource upload, access tracking and barriers still execute
before the wrapper decides whether its binding values changed. No resource
lookup or shader-specialization work is skipped.

## Invalidation and Vulkan state

Target changes, every new session (even a reused command-buffer handle), generic
Set callbacks, Scheduler::CommandBuffer direct access and shader replacement
invalidate all four command caches. Direct handles retain the existing contract:
reacquire them after Stream calls. RawCommandBuffer remains comparison-only.
Drain/Publish alone do not invalidate state because they preserve command order.

Every named dynamic-state setter, including setVertexInputEXT and the stride
binding wrapper, invalidates the graphics-pipeline cache. It does not disturb
the compute pipeline or index/push-constant snapshots. This deliberately permits
an identical graphics pipeline to be rebound after a dynamic setter: binding
can restore statically specified state. This follows
[Khronos dynamic-state rules](https://docs.vulkan.org/spec/latest/chapters/pipelines.html#pipelines-dynamic-state).

Push constants use exact layout equality; no cross-layout compatibility shortcut
is assumed. Pipeline switches alone preserve their values under
[Khronos push-constant semantics](https://docs.vulkan.org/spec/latest/chapters/descriptorsets.html#descriptorsets-push-constants).
An intervening push, opaque callback or direct access still forces conservative
replacement/invalidation.

The existing atomic resource-reclamation notice is now consumed through one
helper by descriptor pushes and all four filtered command families. Consuming
it invalidates both descriptor and command caches; one consumer cannot hide the
notice from the other cache. Deferred callbacks do not mutate producer-owned
cache arrays. Shader replacement explicitly invalidates both caches before
pipeline/layout handle recycling. Buffer-cache arena, stream and null-index
handles remain owned by their existing lifetime paths; none are destroyed by
the new filter. Resource memory remapping is still handled by resource/cache
synchronization rather than by changing a Vulkan binding tuple.

No barrier, draw/dispatch, rendering-scope command, descriptor-set bind or dynamic
state setter is removed by this implementation. No persistent shader/pipeline
cache format changes are needed for this transient recording state.

## Producer/worker cost measurement

SHAD_COMMAND_STREAM_STATS enables cumulative per-stream diagnostics at most once
per three seconds of session completion. The stream address identifies records
across sessions. Optional clocks are disabled in the normal hot path.

- Each filtered family reports calls, skipped calls and inclusive producer wall
  nanoseconds covering comparison, resource-notice handling, copying and enqueue
  or synchronous recording. These counters exclude item-8 descriptor writes.
- Stream totals report emitted Push records, command-record bytes, auxiliary
  payload bytes actually copied, enqueue nanoseconds, synchronous inline-record
  nanoseconds, Drain calls and Drain nanoseconds.
- Worker totals report replayed commands/chunks and wall nanoseconds inside
  chunk replay. Atomic publication is once per chunk. Idle spin, sleep and
  wake-up time outside replay are excluded; descheduling during replay is
  included. These are wall regions, not exclusive thread-CPU times.
- Enqueue time includes Reserve/Publish/backpressure inside Push, but excludes
  earlier wrapper Reserve/Copy calls. Family time includes those copies. Drain
  includes Publish/wait time. These regions overlap/nest; do not add them into
  an exclusive CPU total. Direct fallback recording and synchronous helpers
  that bypass Push are outside stream totals.
- Total record/copy/replay counters cover all queued command families, including
  forwarded descriptors. Hold descriptor settings constant and use the four
  selected-family skip counters to attribute item-10 effects. Descriptor-cache
  skips retain item 8's separate counters.

The existing benchmark runner extracts first/last cumulative counter deltas per
stream and family within measurement.log into result.json.command_stream_profile.
Missing/single-snapshot/reset counters are unavailable, not zero. Partial edge
intervals are excluded. Stats snapshots use individual atomic loads rather than
a transaction across all fields. Runs enabling any supported diagnostic stats
are now excluded from performance summaries even without --profile.

Presence of SHAD_DISABLE_COMMAND_CACHE disables only these four new filters;
`0` also disables them. Descriptor filtering and item-9 scheduling retain their
independent controls. SOTC_WORKER_RECORD=0 selects synchronous recording.
Inherited SHAD_ variables are already cleared by the runner before explicit
variant variables are applied and recorded.

Use separate diagnostic and uninstrumented timing series after the candidate
build completes, keeping the same seed, route, cache and descriptor settings:

```powershell
python tools/benchmark.py run --executable runtime/Build/roadmap8-x64-Clang-Release-lto/shadps4.exe --matrix docs/benchmark-command-stream-profile.json --out runtime/Build/roadmap10-stream-profile --repeats 1 --caches cold
python tools/benchmark.py run --executable runtime/Build/roadmap8-x64-Clang-Release-lto/shadps4.exe --matrix docs/benchmark-command-stream-control.json --out runtime/Build/roadmap10-stream-comparison --repeats 3
```

Both matrices contain cache off/on with worker off/on. The first uses exact
counters without requiring the approximate stack sampler or a PDB. The second
has optional instrumentation disabled. Follow BENCHMARK_PROTOCOL for matched
representative scenes, repeats, images and a second AMD/NVIDIA PC. Filter hits
alone do not establish a net CPU/FPS benefit.

The pre-change diagnostic series uses the preserved item-9 binary with the old
command stream and both worker modes, empty emulator caches, 35-second warm-up
and 30-second capture. It can contextualize existing render-thread/stage totals;
it has no exact worker-replay/filter counters and no matching PDB for reliable
sampler attribution. Exact producer/worker A/B cost remains pending the new
instrumented binary. This gap is not represented as a zero-cost worker or a
measured item-10 speedup. Raw evidence is under
`runtime/Build/roadmap10-20261017/profile-baseline/`.

Both baseline processes and telemetry exited 0 without matched critical/device
loss/assertion messages. Four 1920x1080 captures were inspected and show the same
opening gesture prompt. Ten approximately three-second CPU windows per mode
report 391-1422 ms render-thread CPU with the worker off and 500-1422 ms with it
on. These variable profiled windows are contextual observations, not a worker
speedup or an item-10 result. Ten direct-stage windows per mode are retained;
their nested times must not be summed. Provenance, conditions and actual windows:
[measurements/20261017-roadmap10-profile.json](measurements/20261017-roadmap10-profile.json).

## Verification and pending acceptance

Changed-range clang-format, Python/JSON parsing and counter-parser validation
are recorded under `runtime/Build/roadmap10-20261017/`. The parser was checked
against absent/single/multiple/reset snapshots without adding repository tests.
Nine Windows x64 clang-cl 19.1.5 syntax checks passed with exit 0 and empty
diagnostic logs: command stream, scheduler, pipeline cache/common, rasterizer,
runtime, tile manager, blit helper and fault manager. Source hashes match the
syntax launch. The full Release/LTO build retains separate build-launch.json,
build-status.json, persistent logs and a visible-console record there.
The source SHA/dirty/hash
snapshot includes local item 9. Successful compilation alone does not establish
GPU correctness or performance acceptance.

Follow-up at the item-11 start: the full Windows x64 Release/LTO build completed
with exit 0. Its expected executable was present and its SHA-256 matched
`D329A30AB2C5FC281C88A7D1C89F54594A3E06947A91F77CB025960540BAD557`.
The executable and metadata are preserved as the item-11 baseline before build
directory reuse. Candidate GPU/performance acceptance remains pending.

Pending correctness/reference workload, suitable for OpenOrbis comparison:

1. Repeat draws/dispatches with identical bindings/constants and deterministic
   readback hashes; independently change buffer handles, offsets, sized-index
   lengths/types, first/count and constant layout/stages/offset/size/bytes.
   Compare cache and worker independently off/on on console and AMD/NVIDIA.
2. Alternate graphics/compute and static/dynamic pipelines. Rebind the same
   graphics pipeline after dynamic setters, generic/direct helper recording,
   blits/tiling/fault processing and pipeline replacement. Confirm first bindings
   after invalidation forward, including reused command-buffer/resource handles.
3. Interleave partial/overlapping vertex/constant writes, legacy/sized index and
   vertex APIs, null index paths, slot/capacity edges, unsupported/large updates,
   chunk boundaries and caller-array reuse before replay. Verify hashes/order.
4. Exercise resource reclamation notifications first through each of the new
   command families and first through descriptors, then use the other family.
   Preserve descriptor lifetime notices, readbacks, labels and guest signals.
5. Run separate Vulkan core/synchronization and GPU-assisted validation, then
   gameplay transitions, effects, shadows, save/load, long resource churn and
   shader replacement in both worker modes. Only one PC is currently available;
   second-PC and validation-layer prerequisites remain in HANDOFF.

Further filters, including dynamic vertex size/stride caching, require separate
state-dependency analysis and measured producer/worker evidence.
