# Roadmap item 4: stencil size and depth association

Target: Windows x86-64, AMD Ryzen, NVIDIA Vulkan, CUSA00004 v1.07.
Base runtime: `f88d3b6f331272ce854bda5875c11386b180f94f` with the retained
local item-1, item-2 and item-3 changes. Implementation remains local and
unpublished; full hardware/gameplay acceptance is not claimed.

## Coherent upstream port

Port all three parts of [#5296](https://github.com/shadps4-emu/shadPS4/pull/5296)
together:

1. Compute stencil_size after guest_size is finalized, as
   `guest_size / (num_bits >> 3)`. Stencil has one byte per sample; the finalized
   depth size includes the actual tiled/linear footprint, samples and layers.
   The previous pitch * visible-height expression omitted those factors.
2. Move the existing stencil lookup/creation/linking from FindDepthTarget into
   TextureCache::AssociateStencil and retain the original target-bind call.
3. Call AssociateStencil for the destination of Rasterizer::DepthStencilCopy,
   using the destination ID and write descriptor. A copy destination need not
   have been bound as a depth target, so its stencil address must be associated
   explicitly before subsequent stencil sampling.

The helper retains matching by guest base address and stencil-compatible (or
undefined placeholder) format, registration of a missing placeholder, LRU touch
and linking through both depth ID and image UID. A zero stencil address remains
a no-op. The destination descriptor uses StencilWriteAddress rather than the
source StencilAddress.

## Local integration review

- Tiled guest_size comes from GetDepthSliceSize times layer count;
  GetDepthSliceSize includes the depth bytes per sample and NumSamples.
  Dividing by depth bytes therefore retains tile padding, layers and samples.
- Linear guest_size is finalized by ImageSizeLinearAligned and multiplied by
  layers before the stencil calculation. Depth NumBits returns 16 or 32, so the
  divisor is respectively two or four bytes.
- GetAssociatedDepth still checks allocation, image UID and registration and
  disassociates an invalid/recycled owner. Shader image binding already uses
  this helper to redirect stencil access to the combined depth-stencil image.
- Local SlotVector storage preserves object addresses on insertion. Creating a
  stencil placeholder does not invalidate the retained depth/image references.
- The existing slice range, copy extent, aspect selection, image transitions,
  recorder draining and dirty/GpuModified flags in the runtime copy are retained.
  This port does not redefine depth-only versus stencil-only copy selection.
- Sharp-descriptor memoization, image lookup memoization/generation invalidation,
  depth/float parked-twin reuse, shadow handling, readback and renderer fast paths
  are preserved. Placeholder creation still uses RegisterImage, which increments
  the local image-set generation. No layout or cache-version change is introduced.

The existing candidate-selection policy is retained rather than adding a new
alias/GC redesign. Same-address plane growth and ownership changes remain useful
hardware reference cases below.

## Validation and records

- Follow-up on the item-5 prompt: the full build completed with exit 0;
  executable present and SHA-256 verified as
  `1A2D83DC8E115C72AC076A7A6CCC7FD4B2424C2D0A7B850C454525B29BE4A525`.
  Runtime acceptance remains pending.

- Previous item-3 Release/LTO build: complete, exit 0, executable present and
  SHA-256 verified as `AEFB05233E73EB5EDB832C412416D2F98EC004251B62440DD19A92AA1EE1CE15`.
  Its build directory is preserved as the pre-item-4 baseline.
- Windows x64 clang-cl syntax checks passed (exit 0) for image_info.cpp,
  texture_cache.cpp, image.cpp, vk_rasterizer.cpp and vk_runtime.cpp. Diagnostic
  logs are empty. Project clang-format and whitespace checks passed. Evidence:
  `runtime/Build/roadmap4-20261016/syntax-launch.json`, `syntax-status.json`
  and per-file response files/logs. Linking and runtime behavior remain separate
  checks.
- Full Windows x64 Release/LTO launch:
  `runtime/Build/roadmap4-20261016/build-launch.json`; final result belongs in
  `build-status.json`. Expected executable:
  `runtime/Build/roadmap4-x64-Clang-Release-lto/shadps4.exe`.
  Durable logs, source hashes and dirty state are recorded by the worker.
- Separate native log windows use open-windows-build-console.ps1, with records
  in `syntax-console-launch.json` and `console-launch.json`. No desktop input,
  activation or computer-use automation is used. Closing a viewer leaves the
  worker running; the full-build result stays visible until Enter is pressed.
- No repository tests were added, following runtime/AGENTS.md. No console run,
  game launch, Vulkan validation run or benchmark is claimed. No FPS effect is
  asserted.

## OpenOrbis hardware reference cases to share

Use an OpenOrbis graphics sample with distinct depth/stencil read and write
addresses. Give each layer a recognizable stencil pattern, perform the copy,
then sample/consume the destination stencil without first binding the destination
as a depth target. Record descriptors, dimensions, tile/slice registers, sample
and layer counts, return/log results and per-layer readback hashes on console
and on the Windows AMD/NVIDIA emulator. These are pending reference cases.

| Case | Procedure and comparison |
| --- | --- |
| Copy destination association | Bind/populate only the source target, copy to separate destination depth/stencil addresses, then sample the destination stencil as R8. Repeat after binding the destination as a target; both paths must resolve to the same destination owner. |
| Plane size | Compare Z16 and Z32 with 1/2/4/8 samples and one/multiple layers. Include visible-height hints smaller than the padded tiled height, linear aligned surfaces and accesses at the final layer/page. Check that samples/layers/padding remain in the registered stencil range. |
| Selected slices | Copy nonzero starting slices and partial layer ranges; compare copied slices and sentinel contents of untouched slices. |
| Existing/new plane | Start with no stencil placeholder, an existing compatible R8 image and an undefined placeholder. Check reuse, then rebind the same stencil address with a larger plane/layer count. |
| Ownership and lifetime | Reuse a stencil address for another depth destination; unregister/destroy the old depth owner and recycle its slot. Confirm ID plus UID validation prevents a stale depth association. Check zero stencil addresses. |
| Copy aspects and readback | Exercise depth-only, stencil-only and combined copy requests and inspect both resulting planes. Preserve separate expectations from console observations rather than assuming these source ports change aspect-selection policy. |
| Shadows/aliasing | In CUSA00004 v1.07 check stencil-dependent effects, Seattle shadows/lighting, depth/float switches, particles, transitions and save/load. Compare parked-twin reuse enabled and disabled. |
| Synchronization/worker | Run core/synchronization validation with SOTC_WORKER_RECORD enabled and disabled, separately from timing. Include stencil reads immediately after copies and address/owner reuse. |

Console references, Khronos-layer validation and gameplay/readback acceptance
remain pending. Any performance work must follow BENCHMARK_PROTOCOL.md and place
actual measurements in PERFORMANCE_LOG.md.
