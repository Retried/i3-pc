# Roadmap item 12: GC and image readback

Local adaptation of upstream [#3396](https://github.com/shadps4-emu/shadPS4/pull/3396),
reviewed against commit
[`e6faa2e3b6794a2fa79a709352ddfccfaa817ed1`](https://github.com/shadps4-emu/shadPS4/commit/e6faa2e3b6794a2fa79a709352ddfccfaa817ed1).
This is a separate implementation following
[item 11](ROADMAP11_READBACK_20261017.md), retaining its mapping generations,
expected-byte commits, mirror reservations and separate
[CMask port](ROADMAP11_CMASK_20261017.md). Source integration does not establish
runtime or performance acceptance.

## Dependency and lifetime policy

Image download now completes on the recording producer: snapshot and mapping
capture, image-to-buffer copy/tiling, existing Scheduler::Finish, host invalidate,
conditional commit, staging release, buffer-cache notification, then eviction.
The image remains registered until its readback succeeds. A later producer
cannot reuse the guest address while an old image callback waits to commit.
The priority thread no longer commits image downloads or releases their staging
allocations. Deferred Vulkan image/view destruction and the command/descriptor
cache reclamation notification remain intact.

The dedicated download allocation is held across recording, submission, GPU
completion and CPU consumption. Release runs on the producer. Both synchronous
linear-image processing and GC use this path; no wait was removed. Mapping
replacement rejects old bytes, and expected-word commits retain observed CPU
changes, including physical aliases. A conflicting or stale commit retains the
image rather than declaring the eviction successful. Value ABA and independent
alias page-watcher reference counts remain item-11 limitations; this change does
not claim to implement CPU store generations.

Writable buffer acquisition and pending mirrors mark overlapping images
MaybeGpuDirty, including currently known direct-memory aliases. Image copies and
expansion propagate this uncertainty. A normal image upload consumes current
buffer/guest contents and clears the marker. GC does not clear it merely because
an image was touched or a hash matches. This deliberately differs from upstream's
MaybeGpuDirty hash heuristic: equality cannot prove absence of a newer producer,
and discarding a whole image after a partial buffer write needs stronger evidence.
Uncertain GPU-valid images are retained. Already dirty images continue to use the
existing CPU/buffer-authoritative eviction policy. Unsupported downloads also
remain resident; memory-pressure progress for such cases requires hardware
acceptance, not an allocation-over-budget retry.

Committed image bytes mark buffer-cache pages CPU-modified at the original VA
and direct aliases and advance the stream reuse epoch. No neighboring GPU dirty
bits, exact modified ranges, pending mirrors or mirror snapshots are erased.
Subsequent buffer uploads therefore see the readback without losing another
producer sharing the same page. The readback gate also rejects an outstanding
GPU buffer range. Local whole/changed-word mirror policies, frame lead and urgent
completion signals remain unchanged.

## Full image layout

Downloads allocate the complete guest footprint and copy every mip and layer,
with volume depth reduced per mip. Each copy is checked against its mip capacity,
pitch, height and element alignment before recording. Single-sample images with
the exact guest/host format and no combined stencil plane are supported; uncertain
format conversion, MSAA, combined depth/stencil and oversized single-dispatch
tiling stay resident rather than recording an invalid Vulkan copy.

The staging output is seeded with the captured guest bytes. Linear copies leave
row/layer padding intact. Tiled copies reuse TileManager and its existing macro/
micro tilers, with a padding-preservation mode that writes only real texels/BC
blocks and slices. The shader checks mip, descriptor and padding bounds, handles
offset gaps, and the tiler rounds up its dispatch. Its packed pitch/height keeps
the existing 12-byte mip ABI without requiring 16-bit uniform storage. Other
tiler callers retain their default padding policy.

The tile input staging allocation uses synchronized reuse. Transfer writes are
made visible to compute reads, destination accesses are checked, and compute
reads/writes are registered with Runtime. This preserves reuse barriers in
addition to the image layout transition and host completion wait.

## Collection and accounting

UniqueImage charges actual VMA allocation bytes at creation and releases the
charge only at destruction. Moves transfer ownership and size exactly once,
including destruction of an assignment's old allocation. The fallback total
therefore includes alternate sample backings, parked depth/float twins and images
queued for deferred deletion. Device heap usage remains the pressure source when
VK_EXT_memory_budget is available. Heap usage and live allocation bytes are
different measurements because allocator blocks may remain cached.

The local slot-pressure trigger at MAX_IMAGES / 2 remains. Normal/pressure/
critical collection selects at most 10/20/40 candidates and scans at most 256
images per invocation. Ages are 16/8/1 GC ticks: increased pressure admits younger
resources while retaining the current tick. Skipped candidates rotate through
LRU so an uncertain prefix cannot indefinitely hide reclaimable images. The LRU
helper now checks the callback's actual result type; previously it compared the
invoke_result trait itself with bool and ignored early termination. This also
restores the sampler collector's existing deletion limit.

Pressure collection completes deferred destruction after its successful
evictions and resamples memory usage. Unregistering an image is no longer counted
as freeing its Vulkan memory. No unbounded allocation retry or portability path
removal is included. Optional SHAD_GC_STATS logs tick, occupied slots, live image
allocation bytes, pressure usage, scan/retention and eviction counts. It is a
diagnostic control; keep it out of timing comparisons.

## Validation records

No repository tests were added. Changed-range formatting passed for ten C++
source/header files. Fourteen Windows x64 clang-cl 19.1.5 syntax checks and all
twelve micro/macro tiling shader variants passed with exit 0. C++ diagnostic logs
are empty, checked runtime hashes match the syntax launch, and both repositories
passed diff whitespace validation. The first syntax attempt caught an unsupported
SmallVector initializer; the corrected source passed the complete second run.
These checks have records
under `runtime/Build/roadmap12-20261017/`: `format-status.json`,
`syntax-launch.json`, `syntax-status.json`, per-source logs and shader SPIR-V.
Full Windows x64 Release/LTO validation uses `build-launch.json`,
`build-status.json`, persistent logs and a separate visible console launch record.
SHA/dirty state and file hashes include the retained items 9-11 changes.
The full build completed with exit 0; the expected executable was verified at
the item-13 prompt with SHA-256
`5B153E66AAEFC816FC1E8BE60960DF26551D26F860D2A219BE39C3C3E6322D06`.
Item-13 cold/warm diagnostics subsequently exercised the opening gesture control;
they do not establish GC pressure recovery or representative gameplay acceptance.

The item-11 build was checked once before editing: exit 0, expected executable
present, SHA-256
`C84F07B10843E58575DE8913D19211E0D30271DC54162EC7F577F9E21AE96BA7`.
The launch preserves that executable and its metadata as the item-12 baseline.

## Pending OpenOrbis reference and pressure acceptance

Share the following deterministic OpenOrbis hardware workload with its PC
reproduction. These are required reference cases, not executed console results.
Use distinct pattern/checksum values per producer, mip, layer and iteration.

1. Render/store into linear, micro-tiled and macro-tiled images, complete mip
   chains, layered arrays and 3D images. Include BC 64/128-bit blocks, depth-only,
   odd dimensions and padded rows/slices. Fill padding with CPU sentinels first.
   Force eviction, read via a raw buffer and CPU, then rebind as an image. Verify
   every texel/block and that padding and adjacent allocations retain sentinels.
2. Interleave raw buffer writes and image writes at equal, interior and partial
   ranges, including two VAs for one physical range. Delay mirror consumption.
   Force pressure before and after consumption and before/after image refresh.
   Verify the latest producer and that uncertain images are retained rather than
   overwriting newer buffer data. Exercise copies/expansion of marked images.
3. Write CPU sentinels during image copy completion; unmap/remap one/all pages
   to different and identical physical backing. Verify conditional commits,
   replacement mappings, partial conflicts and subsequent buffer uploads. Repeat
   with pending urgent/full mirrors crossing the 32-MiB reservation wrap.
4. Place two independent GPU outputs and an image on one tracking page. Evict
   only the image, then consume both outputs. Their dirty state and completion
   signal ordering must survive. Repeat through physical aliases and with
   descriptor/command caches enabled and disabled.
5. Allocate more than 32768 small textures with modest byte usage to trigger
   slot pressure independently of heap pressure. Also cycle large textures,
   multisample alternate backings and parked depth/float twins. Observe bounded
   scans/deletions, eventual slot reuse after deferred destruction and allocation
   accounting across move/recreation. Unsupported and uncertain cases must not
   be silently discarded to satisfy the pressure target.
6. Run CMask owner/address/UID reuse, consumed clear masks and supported sample
   encodings from item 11. Eviction must unregister only the departing owner;
   metadata reads and page-neighbor data must remain correct.

Run at least 45 minutes per worker mode on Windows AMD Ryzen/NVIDIA with
CUSA00004 v1.07: repeated resource-heavy routes and save/load/scene transitions,
plus the separate allocation workload above. Record executable/source hashes,
settings, driver, start/end time, peak/steady process and heap memory, slot/
allocation/retention counters, checksums, crashes, rendering captures and exit
status. Include at least ten pressure/recovery cycles and a final idle/reuse phase
to distinguish cached allocator blocks from unbounded live allocations. Diagnose
SHAD_GC_STATS in separate runs; follow BENCHMARK_PROTOCOL for matched unprofiled
baseline/candidate timings. Run core/synchronization and GPU-assisted validation
separately when Khronos layers are supplied. A retained-image plateau, slot
exhaustion or failed recovery is a failed acceptance case, not a speedup.

Only one AMD/NVIDIA PC is available, no console reference or Khronos layer has
been supplied, and the previous automated seed reaches the opening gesture
prompt. Long pressure/gameplay, second-PC and console acceptance remain pending.
