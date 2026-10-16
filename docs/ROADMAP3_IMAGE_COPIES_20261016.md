# Roadmap item 3: layer and mipmap buffer copies

Target: Windows x86-64, AMD Ryzen, NVIDIA Vulkan, CUSA00004 v1.07.
Base runtime: `f88d3b6f331272ce854bda5875c11386b180f94f` plus the retained
local item-1 and item-2 ports. This is a local implementation, not a published
upstream merge or a claim of gameplay acceptance.

## Upstream package and local adaptation

Port [#5299](https://github.com/shadps4-emu/shadPS4/pull/5299) together with
[#5368](https://github.com/shadps4-emu/shadPS4/pull/5368).
CopyImageWithBuffer copies the shared layer count and every shared mip level,
rather than asserting equal layers and a single mip. Each mip has its own extent
and a 16-byte-aligned staging offset. Shared extents are bounded by both images.
The same region layout is used for download and upload; only the aspect changes.
Extra destination layers/mips are untouched by this copy.

The local caller previously requested a fixed 128 MB staging allocation. Merely
adding mip regions would allow larger layer/mip chains to exceed that allocation.
CopyImageWithBuffer now owns the staging request, sized from the complete region
layout including alignment gaps. The pool's returned base offset is added to
every region; the backing-buffer capacity is checked before recording commands.
The existing staging pool, ring/dedicated allocation policy and reuse remain.

BufferImageCopySize uses 64-bit arithmetic, rounds block dimensions up and uses
the actual copied depth/stencil plane format. This matters for combined formats:
a D32_SFLOAT_S8_UINT depth copy uses four bytes per texel and its stencil copy one,
not the combined image's byte width. The helper is also used by UploadImage and
DownloadImage, so their dependency ranges use the corrected plane/block sizes.
Source/destination packed mip byte sizes must match before a reinterpretation
copy is issued. These are byte reinterpretations, not numeric format conversions.

Reference: [Vulkan buffer-image addressing and depth/stencil aspect formats](https://docs.vulkan.org/spec/latest/chapters/copies.html).

## Synchronization and existing paths

Keep SetBackingSamples handling and whole-image source/destination transitions.
Before the staging write, check both earlier reads and writes across the full
allocation. Keep the image-to-buffer / transfer-write-to-transfer-read barrier /
buffer-to-image sequence. Record both staging accesses for subsequent users.
The command-buffer access still drains the recorder through Scheduler; no worker
bypass was introduced.

The texture-cache depth/float parked-twin selection and reuse code is untouched.
CopyColorAndDepth still chooses direct image copies when supported, uses the
buffer path for color/depth reinterpretation, and preserves its multisample
paths. Stencil association/size changes remain roadmap item 4.

## Validation and records

- Previous item-2 Release/LTO build: complete, exit 0, executable present and
  SHA-256 verified as `F7E64DF9FCB470BEF518ADF5156B154CF47221EAEAD49E271383E471B8150A4A`.
  The item-2 build directory is preserved as the pre-item-3 baseline.
- Windows x64 clang-cl syntax checks passed (exit 0) for vk_runtime.cpp,
  texture_cache.cpp, vk_rasterizer.cpp and vk_staging_buffer_pool.cpp; diagnostic
  logs are empty. Compiler evidence:
  `runtime/Build/roadmap3-20261016/syntax-launch.json`, `syntax-status.json`
  and per-file response files/logs. Syntax success does not establish linking
  or runtime correctness. Project clang-format and whitespace checks passed.
- Separate syntax log-console record:
  `runtime/Build/roadmap3-20261016/syntax-console-launch.json`.
  The viewer also replayed the completed syntax log under Windows PowerShell
  5.1 with exit 0, matching the engine used for separate console windows.
- Full Release/LTO build launch:
  `runtime/Build/roadmap3-20261016/build-launch.json`; final result belongs in
  `build-status.json`. Expected executable:
  `runtime/Build/roadmap3-x64-Clang-Release-lto/shadps4.exe`.
  The worker records source hashes/dirty state and persistent stdout/stderr.
  Its separate visible log window is recorded in `console-launch.json`.
- No repository tests were added, following runtime/AGENTS.md. No game run,
  console reference run, Vulkan validation run or benchmark is claimed.
  No FPS effect is asserted.

## OpenOrbis hardware reference cases to share

Use an OpenOrbis graphics sample with a different deterministic pattern in every
mip and layer. Record image dimensions, formats, mip/layer counts and color/depth
readback hashes on a console, then compare with the Windows AMD/NVIDIA emulator.
The following cases are pending references, not recorded passes.

| Case | Procedure |
| --- | --- |
| Shared layers | Copy 1 to 4, 4 to 1 and 2 to 5 layers. Check all shared layers and sentinel contents in untouched destination layers. |
| Shared mip chain | Use equal and unequal mip counts, including more than eight levels, odd dimensions, 1xN/Nx1 tails and 1x1 final mips. Verify every shared level, not just level zero. |
| Staging offsets | Alternate small copies that use nonzero ring offsets with dedicated large copies. Check alignment gaps and copies exceeding the former 128 MB limit. For example, two 4096x4096 R32 layers need 128 MB at mip zero alone, plus their remaining mips. |
| Plane layouts | Compare D16/R16 and D32/R32 reinterpretation, including depth planes of combined depth/stencil images. Check 8-byte and 16-byte BC block tails in upload/download range accounting. Confirm unsupported packed-size mismatches are detected. |
| Synchronization | Alternate source writes, reinterpret copies, destination reads and staging reuse. Run core/synchronization validation separately; check recording enabled and disabled via SOTC_WORKER_RECORD. |
| Depth/float reuse | Repeatedly switch one surface between depth target, sampled float, storage and render-target bindings; compare with SOTC_NO_TWINS set and unset, checking every shared mip/layer. |

CUSA00004 v1.07 still needs scene-transition, lighting/shadow, particle-heavy
combat, depth/float/readback and save/load acceptance. Khronos-layer availability
and console hardware references remain separate prerequisites. Performance work
must follow BENCHMARK_PROTOCOL.md and record actual data in PERFORMANCE_LOG.md.

## Visible build consoles without desktop automation

The user's latest instruction supersedes the earlier bottom-panel requirement.
Agent builds now open a separate console using Start-Process -WindowStyle Normal
and tools/open-windows-build-console.ps1. The worker remains detached and hidden;
the window only reads persistent logs and shows the final status. It remains open
after completion until Enter is pressed, unless CloseOnExit was explicitly used
for a short diagnostic. Closing the viewer leaves compilation running.

No computer-use tool, injected keyboard/mouse input or activation automation is
used to launch or manage these consoles. The standard launcher opens the window
by default; custom build workers use the same helper. AGENTS.md and W1_WINDOWS.md
record this preference for subsequent work.

Full Release/LTO build result, checked at the item-4 prompt: complete, exit 0,
expected executable present and SHA-256 verified as
`AEFB05233E73EB5EDB832C412416D2F98EC004251B62440DD19A92AA1EE1CE15`.
Evidence: `runtime/Build/roadmap3-20261016/build-status.json` and its launch
record. The directory is retained as the pre-item-4 baseline. Console, validation
and gameplay acceptance above remain pending.
