# Delivery summary: roadmap items 1-8 and Xbox prompts

## Roadmap integration

The existing `codex/roadmap-1-8` and `codex/roadmap-1-8-runtime` branches
contain the completed source work below. This publication adds the independent
Xbox prompt changes and integrates the combined result into `main` (wrapper)
and `runtime` (emulator). Both branch families share the existing origin
repository; their histories and roles remain separate. The wrapper submodule
pins the integrated runtime commit.

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

## Xbox prompt changes from this chat

- Reuse the existing hash-based texture pack, image cache and upload path.
  Guest UVs, layout, animation and shaders remain responsible for rendering.
- Add Auto, PlayStation, Xbox and Keyboard/Mouse to the in-game Controls section.
  Preserve legacy force.txt values and persist live selection changes.
- Detect recognized Xbox controllers at startup and from meaningful input before
  overlays consume events; retain original artwork for unknown devices unless
  the user selects Xbox. Controller input mappings and gameplay are unchanged.
- Generate original procedural A/B/X/Y, LB/RB, LT/RT, LS/RS and Menu symbols as
  cached sparse atlas patches. Generate them during Windows packaging and through
  Keys.ps1 without requiring or distributing game artwork.
- Preserve unsupported touchpad/motion artwork. D-pad, separate glyph textures,
  the controller diagram and atlas mips beyond level zero retain their originals.
- Correct style invalidation so refreshing one image cannot suppress updates of
  other resident prompt images. Make unknown-glyph diagnostic readback opt-in.

Architecture, modified files, patch format and manual acceptance procedure:
[Xbox prompts](XBOX_PROMPTS_20261017.md).

## Validation and limits

All eight roadmap Windows x64 Release/LTO builds completed with exit 0. The
combined roadmap-plus-Xbox build also passed, with matching executable SHA256
`5454EF744091890C7DCB59ED3166369ADF3D27A4D8711C4AC96F8E2C7966EC2C`.
Its durable launch/status records are in `runtime/Build/xbox-20261017/`.
The worker confirmed unchanged source during compilation; the pre-merge runtime
working files are the tested source. Merge commits do not add runtime source edits.

PowerShell parsing and changed C++ formatting checks passed. Offline checks
verified 21 disjoint Xbox patch regions and preserved touchpad bounds. Keyboard
atlas and Controls diagram generation matched the pre-change outputs byte for
byte using identical bindings and a synthetic atlas. Deployment without game
artwork generated the same Xbox patch, retired the legacy generated Xbox atlas,
and left input configuration and the saved prompt style unchanged.

No game was launched for the Xbox feature. Actual controller switching, UI
persistence/restart, guest texture restoration, Vulkan validation and complete
prompt coverage still require in-game acceptance. Roadmap hardware references,
save/load/readback acceptance, second-PC checks and matching performance A/B
measurements also remain pending. No FPS gain or full artwork coverage is claimed.
