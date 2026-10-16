# Roadmap item 5: BC layout tables

## Scope and integration

Ported [upstream #5307](https://github.com/shadps4-emu/shadPS4/pull/5307),
commit `8d9c8247b0c23e360aabcbff30e57c2106df6d38`, onto the local runtime
based on `f88d3b6f331272ce854bda5875c11386b180f94f` with items 1-4 retained.
The downloaded patch is retained in `runtime/Build/roadmap5-20261016/5307.patch`.

Both constexpr BC layout tables now contain 12 entries, for square dimensions
1 through 2048. Their shared MAX_DIM_LOG2 also bounds the lookup using
bit_width(pitch). The existing generator and every other eligibility condition
are unchanged: power-of-two square pitch/height, depth/layers/samples equal to
one, complete mip chain, block-compressed power-of-two layout, no alternate
tiling and Thin1DThin. Only 64- and 128-bit BC blocks use these tables.
4096, rectangles, partial chains and other ineligible descriptors retain the
general ComputeImageSize path. No new pixel-format include is needed locally.
Sharp descriptor memoization, renderer paths and cache serialization are unchanged.

## Validation

- Follow-up on the item-6 prompt: the full build completed with exit 0;
  executable present and SHA-256 verified as
  `9FE18B5B371A6DEA77DF6DF1ADB3F6F1D1E3B86862884A550352C4665D244D9C`.
  Runtime acceptance remains pending.

- The preceding item-4 Windows x64 Release/LTO build completed with exit 0.
  Its executable is present and SHA-256 verified:
  `1A2D83DC8E115C72AC076A7A6CCC7FD4B2424C2D0A7B850C454525B29BE4A525`.
  That build is preserved as the pre-item-5 baseline.
- Windows x64 clang-cl syntax check of image_info.cpp, including both constexpr
  tables, passed with exit 0 and empty diagnostic log. Project formatting and
  whitespace checks passed. Records: `runtime/Build/roadmap5-20261016/`
  `syntax-launch.json`, `syntax-status.json` and compiler response file/log.
- Inspected clang's evaluated constexpr values directly using its AST dump of
  the actual image_info.cpp translation unit. Checked every active mip's size,
  pitch, height and offset against square BC payload arithmetic with a minimum
  8x8-block microtile, along with total size and zero macro-to-micro mask.
  Both tables have 12 entries and 78 active mips each. All checked values match;
  each new 2048 entry has a complete 12-level chain and four zero unused slots.
  Evidence: `bc-layout-ast.log` and `bc-layout-values.json` in the same directory.
  This host inspection does not establish console rendering correctness.

| BC block bytes | 2048 base mip bytes | Full chain bytes | Final 1x1 mip offset / padded bytes |
| --- | --- | --- | --- |
| 8 | 2097152 | 2798592 | 2798080 / 512 |
| 16 | 4194304 | 5597184 | 5596160 / 1024 |

- Source review confirms that 1024 still indexes entry 10, 2048 now indexes
  entry 11, and 4096 fails the capacity guard. The existing single-bit check
  rejects zero before indexing. Prior dirty source changes are preserved.
- Full Windows x64 Release/LTO build launch record:
  `runtime/Build/roadmap5-20261016/build-launch.json`; result belongs in
  `build-status.json`. Expected executable:
  `runtime/Build/roadmap5-x64-Clang-Release-lto/shadps4.exe`.
  Source snapshots, persistent logs and the separate native console launch
  record accompany it. No desktop control or input automation is used.
- No repository tests were added. No gameplay, Vulkan validation, console run
  or benchmark is claimed; no FPS effect is asserted.

## Pending OpenOrbis hardware reference cases

Share an OpenOrbis graphics sample with explicit per-mip compressed blocks,
distinct mip colors/patterns and sentinel padding. Record descriptors, every
mip offset/pitch/size and readback hashes on console and Windows AMD/NVIDIA.

- Exercise complete 2048 chains for BC1/BC4 (8-byte blocks) and BC2/BC3/BC5/
  BC6/BC7 (16-byte blocks), including the 4x4, 2x2 and 1x1 tails.
- Compare 1024 and 2048 eligible descriptors, then 4096, rectangles, incomplete
  chains, arrays and alternate tiling through the general fallback. Compare
  each mip's sampled output, adjacent memory sentinels and allocation bounds.
- Repeat uploads, readbacks, address reuse and texture aliasing; run core and
  synchronization validation on NVIDIA with the recording worker on and off.
- Check CUSA00004 v1.07 texture detail, transitions and save/load. Console,
  Khronos-layer and gameplay acceptance remain pending.
