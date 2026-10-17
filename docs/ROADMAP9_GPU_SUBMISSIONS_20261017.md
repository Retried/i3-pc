# Roadmap item 9: GPU polling and periodic submission groups

## Scope and evidence before the change

Runtime base: `ace6fae75337d8cd192f846fe5ece548ea7836e8`, retaining items 1-8
and the Xbox prompt work. This implements conservative redundant-poll removal
and submission-relative periodic grouping. It does not introduce a polling timer,
change readback dependencies, move callbacks to another thread or batch draws.
Performance acceptance is pending; no FPS improvement is claimed.

The pre-change diagnostic run used the preserved Windows x64 Release/LTO binary
SHA-256 `5454EF744091890C7DCB59ED3166369ADF3D27A4D8711C4AC96F8E2C7966EC2C`.
The run records both its original dirty build metadata and the clean source
state at capture. The binary/seed/harness copies remain under
`runtime/Build/roadmap9-20261017/profile-baseline/`.
Hardware: Ryzen 7 5800X3D, NVIDIA RTX 2070 SUPER, Windows 11 build 26300,
driver 32.0.16.1742, 34,253,664,256 bytes RAM. One PC is available.

The existing benchmark-control matrix requested 35 seconds of warm-up and a
30-second capture with SOTC_PROFILE enabled, empty emulator caches and an
uncontrolled driver cache. The process and telemetry exited 0. Both 1920x1080
screenshots were inspected: the seed actually enters the opening cinematic and
sideways-controller gesture prompt. The title-control label is invalid; this
run is diagnostic only and excluded from performance comparisons. Original
saves were not written. New matrices use an explicitly seed-dependent label.

Nine approximately three-second log windows show 0 ms stream/fault wait totals
and 0-1 ms in Scheduler::Wait (integer milliseconds). These values are inclusive,
rounded and do not cover every semaphore waiter. The existing log's `submits`
field actually receives DrawStats::frames; it is not a vkQueueSubmit count.
Exact timeline-read and queue-submit counts/durations are unavailable in this
baseline. The Release/LTO binary has no matching PDB: export-only symbolization
produced unusable attribution and was rejected. No function percentages are
accepted from that attempt. Earlier W4 sampler evidence concerns another binary
and machine; it is not a measurement of this change.

Compact provenance and the actual wait windows:
[measurements/20261017-roadmap9-profile.json](measurements/20261017-roadmap9-profile.json).
This incomplete profile does not justify timer throttling, larger batch sizes
or removing waits. The implementation instead removes work whose redundancy can
be established from the queue/tick state, and adds exact optional counters for
the remaining profiling gate.

## Implementation and dependency audit

| Path | Change and correctness boundary |
| --- | --- |
| PopPendingOperations | Keep the recursive queue lock and FIFO callbacks. Skip the timeline read for an empty queue or a first incomplete callback at an unsubmitted tick. Execute already-known-complete callbacks without another read. An incomplete submitted front still causes an immediate refresh on every call. |
| SubmitExecution | Remove its unconditional refresh before BeginSession. PopPendingOperations refreshes submitted callback dependencies when needed. Command pools still refresh on pressure before growing; no resource reuse is inferred from an uncompleted tick. |
| Semaphore::Refresh | Perform one driver counter read, then publish the monotonic maximum with CAS. A competing waiter or spurious CAS failure retries publication without another Vulkan query. Keep acquire observations/release publication and never lower the known GPU tick. |
| Periodic submissions | Move the helper counter from a function static to its Scheduler. Reset it at every actual submission, including forced flushes, so a forced handoff cannot be followed by an almost-immediate periodic flush for the same work budget. The default 512 helper calls, SOTC_SUBMIT_EVERY override and zero-disable semantics remain. |
| Wait/Finish/IsFree | Keep forced submission before waiting, the existing title-specific spin policy, blocking waits and explicit IsFree refreshes. No wait or completion condition is weakened. |
| Readbacks/signals | Preserve urgent mirror submissions, deferred labels/signals, CompleteDeferred, fault/staging pressure checks and priority-thread waits. Callbacks stay on their existing paths, including the descriptor-resource invalidation notice. No frame-lead limit, mirror write rule or CPU mapping check changes. |

An empty callback queue cannot make a callback runnable. The current logical tick
has not yet been submitted/signalled, so refreshing cannot make its callbacks
runnable either. Submitted incomplete ticks are never subject to a time/call
throttle. ResourcePool is the only direct consumer of KnownGpuTick outside the
semaphore and still refreshes before overflow. Other pressure decisions retain
Scheduler::IsFree/Wait. This can conservatively retain an allocation until the
next observation; it cannot reclaim an allocation early.

Resetting the periodic counter does not raise its helper-call budget between
submissions. Forced flushes, semaphore/fence boundaries, queue locking, upload
ordering, on_submit/on_session callbacks and command-stream drains are retained.
The push-descriptor cache and its lifetime notifications remain independent.

## Controls and diagnostics

- Default: optimized paths enabled, counters disabled.
- Presence of SHAD_DISABLE_GPU_SCHEDULER_OPT restores eager callback/submit
  polling, driver requery on failed refresh publication and the periodic counter
  spanning forced flushes. A value of `0` also disables the optimization.
- Presence of SHAD_GPU_SYNC_STATS enables cumulative per-scheduler/semaphore
  logs at most once per three seconds of submissions. Timeline handles identify
  each pair; separate schedulers must not be mistaken for a single counter.
- Scheduler counters: poll requests, skipped empty/unsubmitted requests,
  executed callbacks, real queue submissions, periodic submissions, command
  buffers submitted (including upload buffers) and queue-submit API nanoseconds.
- Semaphore counters: refresh calls, real Vulkan counter reads, refresh
  nanoseconds, Wait calls/nanoseconds, spin refreshes and blocking-wait entries/
  nanoseconds. Atomics include priority-thread activity. Snapshots are cumulative
  individual loads, not a simultaneous transactional snapshot. Delta matching
  handles across log timestamps to study rates.
- Wait time includes refresh/spin/blocking time; refresh time also includes
  atomic publication and counter overhead. Do not sum nested times into an
  exclusive CPU total. Queue-submit time excludes the submit mutex, recording
  drain and callbacks. Disabled per-call diagnostics do not read the profiling clock.

The benchmark runner now clears inherited SHAD_ controls and records explicitly
selected ones along with I3_/SOTC_ variables. This also holds descriptor settings
constant rather than letting an inherited cache switch contaminate the series.

After the build finishes, use the existing runner, matching the executable's
build-info.json. Run diagnostics separately:

```powershell
python tools/benchmark.py run --executable runtime/Build/roadmap8-x64-Clang-Release-lto/shadps4.exe --matrix docs/benchmark-gpu-scheduler-profile.json --out runtime/Build/roadmap9-sync-profile --repeats 1 --caches cold --profile
python tools/benchmark.py run --executable runtime/Build/roadmap8-x64-Clang-Release-lto/shadps4.exe --matrix docs/benchmark-gpu-scheduler-control.json --out runtime/Build/roadmap9-sync-comparison --repeats 3
```

The first command intentionally excludes timings from performance summaries.
The second disables optional counters/sampling and provides all four
legacy/optimized and worker-off/on cases. Inspect screenshots to identify the
seed's actual scene. Extend the route only with verified fixtures. Follow
BENCHMARK_PROTOCOL for matching representative scenes and a second AMD/NVIDIA
PC; these matrices alone do not close that acceptance.

## Verification and pending acceptance

Final Windows x64 clang-cl 19.1.5 syntax checks passed with exit 0 and empty
diagnostic logs for scheduler, semaphore, rasterizer and resource pool, including
the diagnostic handle labels. Changed-range clang-format,
whitespace, Python parsing and matrix JSON checks are recorded in
`runtime/Build/roadmap9-20261017/`. No repository tests were added.

The detached full Windows x64 Release/LTO build is recorded in build-launch.json
in that directory, with source SHA/dirty/file hashes, persistent logs and
build-status.json. Its visible log console has a separate launch record. The
previous executable/metadata and diagnostic-run binary remain preserved.
Build completion and candidate GPU execution are not implied by source checks.

Follow-up at the item-10 start: the full build completed with exit 0 and the
expected executable was present with matching SHA-256
`CB2F8823595A86D823A311DC4FB46B0B97DC32DCEFE5B35D055AAE64DC46E296`.
The artifact is preserved as the item-10 baseline before its build directory
is reused. This build result does not close the pending acceptance below.

Pending correctness/reference cases, suitable for an OpenOrbis hardware workload:

1. Copy deterministic compute results to CPU-visible memory before publishing
   a label/event. Chain labels/signals and compare output hashes/order on console
   and Windows AMD/NVIDIA with optimization and worker recording independently
   off/on. Exercise CPU waits, idle command processors and multiple queues.
2. Alternate no callbacks, current-tick callbacks, submitted incomplete callbacks
   and already-complete callbacks. Confirm callbacks run once in FIFO order and
   that CompleteDeferred/Finish make progress without another draw.
3. Force staging/command-pool pressure, priority callbacks, allocation/view reuse,
   upload buffers, mirrors, faults, CPU overwrites and unmap/remap. Check readback
   hashes and descriptor-resource invalidation after reclamation.
4. Interleave explicit Flush, Wait and Finish with helper counts 511/512/513;
   try SOTC_SUBMIT_EVERY=0/1/512. Check queue signals/fences and recording restarts.
   Compare counter deltas and confirm no extra periodic flush immediately after
   a forced submission. Verify long resource-churn sessions do not grow pools.
5. Run separate Vulkan core/synchronization and GPU-assisted validation, then
   target-game transitions, effects, save/load, pacing and extended gameplay.
   Keep descriptor-cache settings identical and do not credit its effect twice.

No timer-based polling reduction, spin-policy retuning or further submit-delay
policy is accepted without exact counter profiles and correctness evidence.
