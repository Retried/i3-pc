# Roadmap item 11: readback dependency and commit guards

## Scope and baseline

This implements a focused dependency/lifetime package and the separate
[CMask port](ROADMAP11_CMASK_20261017.md). It does not import the item-12 GC
redesign or claim that all readback waits can be eliminated. Existing Finish,
Wait, frame-lead limits, synchronization barriers and guest completion paths are
retained. Correctness/performance acceptance remains pending; no FPS gain is
claimed.

Runtime HEAD is `ace6fae75337d8cd192f846fe5ece548ea7836e8` with local items 9-10
retained. At this task's start, item 10's Windows x64 Release/LTO build had
completed with exit 0 and the expected executable's SHA-256 matched
`D329A30AB2C5FC281C88A7D1C89F54594A3E06947A91F77CB025960540BAD557`.
That executable, its build metadata, before-source snapshots and separate
CMask port boundary are preserved under `runtime/Build/roadmap11-20261017/`.

## Producer -> copy -> CPU model

| Phase | Dependency represented in the implementation |
| --- | --- |
| Producer | AddPendingMirror records the destination's backing pointers and per-16-KiB mapping generations. Existing small-output guest-byte snapshots remain the comparison baseline. Reusing a range after remapping discards its obsolete snapshot before recording a new producer. |
| Copy recording | Existing Runtime buffer/image copy paths retain resource access tracking, image transitions, barriers and command-stream drains. Image downloads capture mapping identity before recording the copy. |
| Submission | Mirror reservations record the scheduler tick containing the last copy in the batch, including any earlier copies submitted while obtaining resources. Deferred callbacks retain the existing tick/FIFO mechanism; no per-range GPU completion finer than that submission is invented. |
| GPU completion | Existing semaphore waits/callback conditions establish completion. Invalidate the noncoherent host allocation before reading its bytes. GPU completion does not itself release mirror bytes still needed by a CPU callback. |
| CPU commit | WriteReadback rechecks each destination page's pointer and generation while holding MemoryManager's shared mapping lock. A missing/replaced mapping is skipped, even if its virtual address and physical pointer were recycled. Expected-byte writes use aligned word CAS, with byte handling for edges. |
| Consumption/release | Mirror reservations are released after the CPU copy/merge is consumed, before the existing done callback publishes its label/event. Async image allocations retain their existing deferred-release path. |

ReadbackMapping is transient state, not a serialization format. Mapping
generations live beside AddressSpace's existing backing-page table and are
updated by physical Map and Unmap under the existing MemoryManager mapping
lock. A new mapping always gets a fresh generation; protection changes and
unrelated mapping operations do not invalidate an unaffected page. Existing
VMA merging, direct-alias bookkeeping and renderer portability paths remain.
File/sparse pages without physical backing are not manufactured into writable
readback targets.

The generation table adds one u64 per allocated backing-table entry plus its
top-level table; physical Map/Unmap walks already visit these pages. Each live
readback token contains one pointer/generation pair per covered 16-KiB page.
Large mappings and long sessions still need memory-pressure measurements.

## Aliases, remapping and CPU stores

Virtual aliases resolve to the same canonical physical backing bytes. Expected
values are therefore compared at that backing address, so a changed CPU word
written through another alias prevents the commit as well. Existing page
watching/alias invalidation is preserved. Identity/generation checks and the
write occur under one shared mapping lock, excluding map/unmap between checking
the identity and committing; the old unlocked IsValidMapping check did not
establish that property.

The old changed-word path first copied current CPU bytes and later called
TryWriteBacking. A CPU store between that comparison and memcpy could be lost.
The final commit now compares the expected dispatch word again with CAS. A
different observed CPU value wins; a later CPU store also wins. Current-memory
comparison uses a readback-specific shared-lock wrapper while retaining the
reused scratch buffer and original changed-stretch coalescing. Upload/hash
paths are unchanged. Explicit diagnostic whole/clobber modes retain their
existing byte-overwrite policy but cannot bypass mapping identity checks.

This remains a value-based word policy: CPU A->B->A writes are not observable as
a distinct write generation. Per-physical-page watch-count limitations already
noted in PageManager also remain. These are not evidence for weakening waits;
reference/alias stress cases and the broader item-12 dependency redesign remain
necessary. No claim of complete native CPU/GPU race emulation follows from CAS.

DownloadMemory and synchronous mirrors keep their blocking completion behavior
and now use mapping-checked commits. A readback already in progress cannot write
to a replacement mapping. Dirty-range/page bookkeeping and the existing CPU
write-fault path are retained. This is not a general change to TryWriteBacking
or guest syscall memory semantics.

## Mirror ring lifetime

Both urgent and ordinary asynchronous mirrors share the existing 32-MiB host
buffer. Each live reservation owns its offset/size until its CPU callback has
consumed the results. On wrap/overlap, ReserveMirrorRange waits for the conflicting
copy tick and runs pending operations before reusing those bytes. Disjoint
reservations retain overlap between GPU and CPU work. Earlier code wrapped the
offset without checking outstanding urgent callbacks; the ordinary frame-lead
limit alone did not constrain that path.

The default two-frame lead limit and six-batch guard are retained. Existing
ordinary callback ordering, inflight ranges, skipped uploads, descriptor/command
resource-reclamation notices and stream-epoch updates remain. No callback moves
to a different thread. Reservations cover the copy-to-CPU lifetime independently
of the logical output ranges used for upload suppression.

Normal asynchronous mirrors require a dispatch snapshot for every range.
Unknown/large outputs and urgent batches larger than the ring use the existing
synchronous partial/full path instead of publishing a completion signal without
known output bytes or risking an unguarded asynchronous overwrite. This is a
correctness fallback, not a measured performance improvement. The existing
1-MiB snapshot threshold remains; it is not raised to hide unbounded CPU copies.

## Image readbacks and item-12 boundary

Synchronous image readbacks keep Finish and invalidate before commit. Deferred
linear-image readbacks capture expected CPU bytes and mapping identity before
copy recording, rechecking SafeToDownload under the image mutex. CPU faults
serialized by that mutex cannot pass the eligibility check unnoticed before
the snapshot. The priority callback commits against the captured mapping and
expected values, without accessing a potentially recycled image slot.

Image GC eligibility, slot pressure, deletion scheduling, tiling exclusions,
backing allocation accounting, priority-thread waits and staging allocation
release are not redesigned. Later overlapping GPU producers/GC ownership and
the existing cross-thread deferred staging-release mechanics still need the
item-12 audit and long pressure runs. Capturing an image snapshot adds host
memory/copy cost; it does not prove a speedup. Do not treat this bounded guard
as completion of the broader GC/readback project.

## Validation and build records

No repository tests were added. Changed-range clang-format and twelve Windows
x64 clang-cl 19.1.5 syntax checks passed with exit 0 and empty diagnostic logs:
address space, memory manager, buffer/texture caches, scheduler, rasterizer,
runtime, pipeline common/cache, fault manager, tile manager and blit helper.
The source hashes match the syntax launch. These checks and whitespace
verification have separate records under
`runtime/Build/roadmap11-20261017/`. The full Windows x64 Release/LTO build uses
build-launch.json, build-status.json and persistent stdout/stderr, with a
separate visible-console launch record. Source SHA, dirty state and file hashes
include retained items 9-10. The full build completed with exit 0; the expected
executable SHA-256 was verified on the next prompt as
`C84F07B10843E58575DE8913D19211E0D30271DC54162EC7F577F9E21AE96BA7`.
Candidate GPU execution must be checked separately; compilation is not gameplay
acceptance. The later [item-12 redesign](ROADMAP12_GC_READBACK_20261017.md)
supersedes the original GC/staging boundary above while retaining mapping,
conditional-commit and mirror guards.

No new runtime/performance trial is claimed here. Before any timing comparison,
follow BENCHMARK_PROTOCOL and record real results in PERFORMANCE_LOG. Do not
compare old item-9/10 profiled controls to unprofiled candidate runs.

## Pending OpenOrbis hardware/reference cases

The following workload and expected observations are shared for console versus
Windows AMD/NVIDIA comparison; they have not been executed on a console here.
Use deterministic compute output and CPU checksums, with a label/event only
after the producer and readback copy. Run worker off/on and descriptor/command
caches off/on independently, keeping settings fixed.

1. Dispatch writes four distinct 32-bit patterns into separate words while the
   CPU writes sentinels into surrounding words. Wait for completion and compare
   every word, including unaligned heads/tails and 16-KiB page boundaries.
2. Map one physical range at two virtual addresses. Change an output word through
   the other alias while the copy is pending; verify the changed CPU value wins.
   Include repeated aliases, overlapping physical spans and A->B->A as a separate
   limitation probe rather than silently assuming the value policy detects it.
3. Unmap/remap the same virtual range to different physical memory, then remap
   it to the same physical memory. Keep identical initial bytes to exercise
   mapping ABA. Old readbacks must not alter the replacement mapping. Also
   replace only one page and verify unaffected pages remain eligible.
4. Queue enough urgent/full mirrors to wrap the 32-MiB ring, delaying CPU callback
   processing. Verify old hashes before reuse and completion signals after CPU
   consumption. Include disjoint reservations, zero/small ranges, missing
   snapshots, the 1-MiB threshold and urgent total sizes above ring capacity.
5. Trigger buffer read faults, CPU write faults, synchronous mirrors, frame-lead
   waits, linear-image readback and deferred image destruction. Overwrite CPU
   memory after image snapshot/copy submission. Exercise remapping between GPU
   completion and callback execution and confirm retained waits make progress.
6. Run CMask's separate [reference cases](ROADMAP11_CMASK_20261017.md), then
   core/synchronization and GPU-assisted validation separately. Validate save/
   load, shadows/effects, transitions, extended gameplay and long memory pressure.
   Only one AMD/NVIDIA PC is available; console, second-PC and Khronos-layer
   requirements remain pending in HANDOFF.
