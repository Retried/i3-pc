# Pending continuation

- PC2 Release/LTO build and automatic packaging: the latest 2026-10-16 check found
  final status `failed`, exit 1: source state changed during the build. Do not
  accept this artifact. Its rejected build directory has been removed; inspect
  the retained logs before deciding on a fresh launch. Records:
  `runtime/Build/pc2-20261016/launch.json`, `inputs.json` and `status.json`.
  Those paths were absent locally at the item-1 check later on 2026-10-16;
  recover the prior evidence before treating it as available for inspection.
  Intended output:
  `packages/i3-pc-PC2-20261016.zip`; the older W1 package remains available.
- Generated files were removed from the retained W1 Release/LTO and W2 debug
  build directories. Reconfigure before another incremental build; executable,
  PDB and metadata hashes were preserved. Cleanup evidence:
  `runtime/Build/pc2-20261016/cleanup.json`.
- Only this AMD/NVIDIA PC is available (user reconfirmed).
  The local Khronos-layer prerequisite check is blocked before game launch.
  External acceptance requires a second target PC and validation/reference
  checks; see [W_DELIVERY_20261016.md](W_DELIVERY_20261016.md)
  and [PC2_ACCEPTANCE.md](PC2_ACCEPTANCE.md). Do not mark these checks passed
  from a build result or title-control captures.

- Roadmap item 1: console reference, guest time/DST boundaries and target-game
  input/save/load acceptance remain pending. The successful local build and
  verification evidence are in
  [ROADMAP1_CORRECTNESS_20261016.md](ROADMAP1_CORRECTNESS_20261016.md).
- Roadmap item 2: console references, feature/fallback paths, recording-worker
  paths, Vulkan validation and target-game acceptance remain pending. Successful
  local build evidence is in
  [ROADMAP2_INDEX_BUFFERS_20261016.md](ROADMAP2_INDEX_BUFFERS_20261016.md).
- Roadmap item 3: console references, layer/mip readbacks, depth/float reuse,
  Vulkan validation and target-game acceptance remain pending. Successful build
  evidence is in [ROADMAP3_IMAGE_COPIES_20261016.md](ROADMAP3_IMAGE_COPIES_20261016.md).
- Roadmap item 4: console reference cases, tiled/layered stencil readbacks, owner/address reuse,
  shadows, Vulkan validation and target-game acceptance remain pending; see
  [ROADMAP4_STENCIL_20261016.md](ROADMAP4_STENCIL_20261016.md).
- Roadmap item 5: console mip-chain references, Vulkan validation and target-game
  acceptance remain pending; see
  [ROADMAP5_BC_LAYOUT_20261016.md](ROADMAP5_BC_LAYOUT_20261016.md).
- Roadmap item 6: shader execution, cache reload,
  console references, Vulkan validation and gameplay acceptance remain pending.
  Gather/U64/descriptor-pattern additions still need target-game evidence; see
  [ROADMAP6_SHADERS_20261016.md](ROADMAP6_SHADERS_20261016.md).
- Roadmap item 7: guest syscall references, mount
  lifecycle, overlays and game save/load acceptance remain pending; see
  [ROADMAP7_VFS_20261017.md](ROADMAP7_VFS_20261017.md).
- Roadmap item 8: the cache is integrated and enabled by default;
  Vulkan/gameplay/readback validation and cache on/off comparisons
  with both worker modes remain pending. Coverage and lifetime cases are in
  [ROADMAP8_PUSH_DESCRIPTORS_20261017.md](ROADMAP8_PUSH_DESCRIPTORS_20261017.md).
- Xbox prompts: game/controller/persistence/GPU validation and incomplete artwork coverage are
  recorded in [XBOX_PROMPTS_20261017.md](XBOX_PROMPTS_20261017.md).
- Roadmap item 9: exact synchronization
  counter profiles, legacy/optimized comparisons in both worker modes,
  readback/signal/Vulkan/gameplay and long pool-pressure checks remain pending;
  see [ROADMAP9_GPU_SUBMISSIONS_20261017.md](ROADMAP9_GPU_SUBMISSIONS_20261017.md).
  The pre-change diagnostic seed entered the opening gesture scene rather than
  the requested title control; its symbol attribution was rejected without PDB.
- Roadmap item 10: candidate command-filter
  coverage and producer/worker cost profiles, cache off/on in both worker modes,
  Vulkan/readback/gameplay and resource-lifetime acceptance remain pending; see
  [ROADMAP10_COMMAND_FILTERING_20261017.md](ROADMAP10_COMMAND_FILTERING_20261017.md).
- Roadmap item 11: mapping/physical-alias/CPU-store,
  ring-wrap and signal-order reference cases, CMask owner/clear-state validation,
  Vulkan/gameplay and long pressure acceptance remain pending. Scope and the
  original item-12 boundary are in [ROADMAP11_READBACK_20261017.md](ROADMAP11_READBACK_20261017.md)
  and [ROADMAP11_CMASK_20261017.md](ROADMAP11_CMASK_20261017.md).
- Roadmap item 12: full-layout/padding, partial
  buffer/physical-alias ownership, remapping/CPU overwrite, slot-only pressure,
  deferred accounting, CMask and 45-minute pressure/recovery runs in both worker
  modes remain pending. Reference workloads, conservative retention limits and
  validation records: [ROADMAP12_GC_READBACK_20261017.md](ROADMAP12_GC_READBACK_20261017.md).
- Roadmap item 13: candidate off/on hit coverage,
  exact restoration/prewarm timings, representative gameplay, cache compatibility,
  Vulkan and second-PC/console acceptance remain pending. Baseline profiling only
  covers the opening gesture scene; speculative prewarming stays opt-in. Details:
  [ROADMAP13_PIPELINE_PREWARM_20261017.md](ROADMAP13_PIPELINE_PREWARM_20261017.md).
- Input repair: physical keyboard/Xbox menu, rebinding, opening graffiti and
  touch/motion acceptance remain pending. Source findings, isolated diagnostic
  limitations, build/deployment records and OpenOrbis reference cases are in
  [INPUT_FIX_20261017.md](INPUT_FIX_20261017.md). Do not infer physical-device
  or gameplay acceptance from the scripted virtual pad checks.
  Build launch: `runtime/Build/input-fix-20261017/build-launch.json`;
  installation record: `runtime/Build/input-fix-20261017/deployment.json`.
