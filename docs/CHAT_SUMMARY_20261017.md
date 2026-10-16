# Chat delivery: roadmap items 1-8

This delivery contains the changes requested in this chat, including visible
Windows build consoles. Independent Xbox prompt work is excluded.

| Item | Delivered change | Detailed report |
| --- | --- | --- |
| 1 | Directory removal, timed mutex, HTTP credential-log filtering, paired analog smoothing and Windows guest time/DST corrections. | [Correctness](ROADMAP1_CORRECTNESS_20261016.md) |
| 2 | Index capacity tracking, mapped-range limits, null-index handling and optional maintenance5/6 support with fallback. | [Index buffers](ROADMAP2_INDEX_BUFFERS_20261016.md) |
| 3 | Image layer/mip copies, staging capacity/offset accounting and preserved synchronization/depth-float reuse. | [Image copies](ROADMAP3_IMAGE_COPIES_20261016.md) |
| 4 | Tiled/layered stencil footprint and shared depth/stencil association, including copy destinations. | [Stencil](ROADMAP4_STENCIL_20261016.md) |
| 5 | BC tables and lookup guard extended together to complete 2048x2048 mip chains for 8/16-byte blocks. | [BC layouts](ROADMAP5_BC_LAYOUT_20261016.md) |
| 6 | Indirect vertex/instance IDs, CLAMP/LEGACY preserving NaN, fp64 detection and cache versioning. Conditional additions remain evidence-gated. | [Shaders](ROADMAP6_SHADERS_20261016.md) |
| 7 | Guest VFS normalization, mount replacement/boundaries, virtual root and owned directory paths. | [VFS](ROADMAP7_VFS_20261017.md) |
| 8 | Default-enabled integrated push-descriptor filtering, lifetime invalidation, fallback and diagnostics; standalone patch removed. | [Push descriptors](ROADMAP8_PUSH_DESCRIPTORS_20261017.md) |

Build workers remain detached with durable logs/status; agent-launched builds
open a separate native console without desktop input or activation automation.
The launcher, log viewer, project rules and Windows build guide reflect this.

## Verification and limits

All eight local Windows x64 Release/LTO builds completed with exit 0; targeted
clang-cl, formatting and source-preservation checks are recorded in the reports.
The last build's executable SHA-256 is
`3F25A8F008C39BEECF7E986A6E727D63D399D3F9EE1DE9C966C2F981667F3565`.
Committed runtime files match that build's recorded source snapshot. Two files
also edited by independent Xbox work were recovered and hash-verified against
the pre-Xbox snapshot without changing working files.

Gameplay, OpenOrbis references, Vulkan layer validation, save/load/readback
acceptance and matching performance A/B runs remain pending. No FPS gain is
claimed. HANDOFF retains these checks and links to their detailed procedures.

## Publication

Runtime commit: `b3ecc05347ed363f2bb2c8f6ea60dbb8ae5d567f`.
Wrapper branch: `codex/roadmap-1-8`; runtime branch:
`codex/roadmap-1-8-runtime`. The wrapper pins the published runtime commit.
Separate indexes allow publication without changing the checkout, user index
or HEAD used by the independent Xbox build. The current checkout is deliberately
left in place. Both branches use the existing origin repository.
