# Roadmap item 2: index buffer correctness

Target: Windows x86-64, AMD Ryzen, NVIDIA Vulkan, CUSA00004 v1.07.
Base runtime: `f88d3b6f331272ce854bda5875c11386b180f94f` plus the local
item-1 changes. Those earlier source changes were retained. This is a local,
unpublished port; runtime acceptance is not claimed.

## Coherent upstream package

- [#5278](https://github.com/shadps4-emu/shadPS4/pull/5278): retain
  IndexBufferSize capacity independently of per-draw num_indices. Restore that
  capacity for all three indexed-indirect packet types. Direct indexed draws
  bind the smaller of the draw count and maximum index count; indirect draws
  bind capacity rather than a stale direct-draw count.
- [#5327](https://github.com/shadps4-emu/shadPS4/pull/5327): maintenance6 is
  optional. Enable it only when both its extension and feature are available.
  Without it, allocate and zero-fill a 16-byte device-local index buffer and
  track its transfer-to-index-read dependency. With it, empty/invalid ranges
  bind a null handle with offset zero.
- [#5358](https://github.com/shadps4-emu/shadPS4/pull/5358): a null guest base
  stays null even when index_offset is nonzero; it never becomes a low guest
  address from adding the offset.

## Local integration decisions

Address offsets and requested byte counts use 64-bit arithmetic. The existing
ObtainBuffer interface takes u32 bytes, so cap the mapped byte count before
narrowing and align down to complete 16/32-bit indices. This prevents capacity
multiplication or narrowing from wrapping to an unrelated small buffer.

The local ClampRangeSize fast path previously returned every request smaller
than 1 GB unchanged. Add an opt-in strict argument for index binding: verify the
starting VMA is mapped, stop at holes/reserved areas, and include only contiguous
mapped VMAs. Zero size or an unmapped/out-of-range base returns zero. Existing
callers retain their previous small-buffer fast path.

Query maintenance5's feature as well as its extension before enabling it. When
available, bind the explicit range through bindIndexBuffer2KHR; otherwise retain
legacy bindIndexBuffer. Both calls go through Scheduler::Stream, with a new
CommandStream wrapper copying scalar arguments into its ordered record. Neither
path bypasses the recording worker. The legacy command cannot express the same
explicit range size; it retains the existing whole-host-buffer binding semantics.

Preserve small stream-buffer reuse and its barrier-tracking exemption. Device
buffers and the zero fallback retain normal dependency tracking. Preserve the
checked-indirect-argument path, draw filtering, direct draw fast path and repeated
indirect draws. Include index capacity in the latter's reuse key, while leaving
IndexBufferSize's existing state-change invalidation intact.

Vulkan references:
[bindIndexBuffer2](https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdBindIndexBuffer2.html)
and [maintenance6](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceMaintenance6Features.html).

## Validation and build evidence

- The item-1 Release/LTO build completed with exit 0. Its executable exists and
  matches SHA-256 `8A79BF2D3FD773E4169A112E8F9F997CC4D212A6E72605814E4907D0259ACDF3`.
  Its directory is preserved as the pre-item-2 baseline.
- Windows x64 clang-cl syntax checks passed (exit 0) for memory.cpp,
  liverpool.cpp, buffer_cache.cpp, vk_instance.cpp, vk_rasterizer.cpp,
  vk_command_stream.cpp and vk_scheduler.cpp, using the existing Release/LTO
  flags. Diagnostic logs are empty. Evidence:
  `runtime/Build/roadmap2-20261016/syntax-launch.json`, `syntax-status.json`
  and per-file response files/logs.
- Applied project clang-format and checked the focused diff/whitespace.
- Full Release/LTO build launch record:
  `runtime/Build/roadmap2-20261016/build-launch.json`; final result belongs in
  `build-status.json`. Expected executable:
  `runtime/Build/roadmap2-x64-Clang-Release-lto/shadps4.exe`.
  The build has persistent stdout/stderr, source hashes and dirty-state records.
  Current console policy is documented in W1_WINDOWS.md. Closing a log viewer
  does not stop the worker. Do not infer completion from syntax checks.
- No repository tests were added, following runtime/AGENTS.md. No game launch,
  Vulkan validation, console reference execution or benchmark was performed.
  No FPS improvement is asserted.

## OpenOrbis hardware reference cases to share

Use an OpenOrbis graphics sample with a known indexed triangle/mesh, record the
command sequence and a color/depth readback, and compare console output with the
Windows emulator. Keep index contents and shader inputs deterministic. These
are pending comparison cases, not passed console results.

| Case | Procedure |
| --- | --- |
| Capacity independent of count | Set IndexBufferSize to cover two meshes. Interleave a smaller direct indexed draw and DrawIndexAuto, then issue indexed-indirect draws addressing the second mesh with firstIndex. Repeat for single, multi and count-multi packets. |
| Changing capacity | Alternate capacities and direct/indirect draws with identical shaders/arguments. Verify repeated-draw reuse is invalidated when capacity changes and works for unchanged capacity. |
| Width/offset | Repeat with 16-bit and 32-bit indices, nonzero offsets, draw counts below/equal/above capacity and values whose byte multiplication exceeds 32 bits. Use a small actual mapping for huge advertised capacities. |
| Mapping boundaries | Bind near the end of a mapped area, across adjacent mapped VMAs, and before a hole/reserved VMA. Verify only complete mapped indices are exposed; also check zero capacity and an unmapped base. |
| Null base | Use base zero with zero and nonzero index offsets and both widths. Compare null-handle and zero-buffer fallback behavior on supported target NVIDIA configurations. |
| Host feature combinations | On AMD/NVIDIA only, check maintenance5/6 available and unavailable paths, preserving required robustness2/nullDescriptor. Do not schedule another GPU vendor for coverage. |
| Recording/barriers | Run SOTC_WORKER_RECORD=1 and 0. Check small streamed indices, device-local/GPU-written indices, the fallback's initial zero fill and transitions between them. Inspect core/synchronization validation separately from performance. |

CUSA00004 v1.07 acceptance still needs indexed/indirect geometry, particle-heavy
combat, scene transitions, lighting/shadows, input switching and save/load.
Layer availability and console references remain separate prerequisites. Any
performance comparison must follow BENCHMARK_PROTOCOL.md.

## Build result and current console policy

At the item-3 prompt the full Release/LTO build was verified: complete, exit 0,
expected executable present, SHA-256
`F7E64DF9FCB470BEF518ADF5156B154CF47221EAEAD49E271383E471B8150A4A`.
This establishes build success, not the pending hardware acceptance above.

The latest user instruction permits a separate visible console and prohibits
desktop control. Follow [W1_WINDOWS.md](W1_WINDOWS.md) and the native console
launcher. The earlier bottom-terminal requirement is superseded.