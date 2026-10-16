# shadPS4 upstream intake review - 2026-10-16

## Scope and snapshot

Target: Windows x86-64, AMD Ryzen, NVIDIA Vulkan, CUSA00004 v1.07.
This is a static intake review, not an implementation or performance result.

- Local runtime: `b499ca72329ab179c365ca695570d6d79e57a998`; working tree clean at inspection.
- Last shared official upstream commit: `945dbc3cc3eee80ac3e053b438502ed936fa6bb2`
  (2026-10-06, subgroup barriers, #5285).
- Official default-branch tip returned by GitHub during this review:
  `5aa7ffa3f4f21bba827d7865ed8f69f98f993542`
  (2026-10-15, music service, #5392).
- [Official comparison](https://github.com/shadps4-emu/shadPS4/compare/945dbc3cc3eee80ac3e053b438502ed936fa6bb2...5aa7ffa3f4f21bba827d7865ed8f69f98f993542):
  53 upstream commits after the shared base. This includes the 0.20.0 release
  marker and 0.20.1 WIP marker; version labels alone do not justify import.
- All 53 commits were screened by scope. Selected renderer, shader, input,
  kernel and logging candidates were inspected at patch level and compared
  against relevant local source. Conditional/later items are a scope triage,
  not a claim of complete behavioral validation of every patch.
- The earlier SotC-project snapshot is a different upstream source. Its selected
  resource-pool changes and excluded upload/shader paths remain documented in
  [UPSTREAM_6D2A7388.md](UPSTREAM_6D2A7388.md).

[CI run 38862336590](https://github.com/Retried/i3-pc/actions/runs/38862336590)
for the local runtime SHA completed successfully. Windows SDL build, Windows C++
tests, clang-format and REUSE passed; Linux/macOS and pre-release jobs were
skipped. This establishes CI build/check results, not gameplay, portable package
acceptance or target NVIDIA correctness. No new jobs were launched.

## Recommended intake order

### 1. Small independent correctness fixes

- [#5373](https://github.com/shadps4-emu/shadPS4/pull/5373): local
  `posix_rmdir` still calls `fs::remove_all` (file_system.cpp:664).
  Port the nonrecursive removal and ENOTEMPTY behavior. Check surrounding
  missing-path and host error translation rather than assuming this single
  upstream patch completes all rmdir semantics.
- [#5386](https://github.com/shadps4-emu/shadPS4/pull/5386): local Windows
  `TimedMutex::try_lock_until` returns false immediately for an expired
  deadline; it should attempt `try_lock()`. Small, directly applicable fix.
- [#5330](https://github.com/shadps4-emu/shadPS4/pull/5330): local HTTP request
  logging still prints supplied header values. Port filtering for Authorization,
  Proxy-Authorization and Cookie in both request-header insertion and dumps.
- [#5340](https://github.com/shadps4-emu/shadPS4/pull/5340) +
  [#5377](https://github.com/shadps4-emu/shadPS4/pull/5377): take as a pair.
  Local ControllerOutput does not carry analog origin and calls Axis with its
  default smoothing argument. Preserve custom mouse/right-stick handling,
  remapping, gestures and scripted/virtual-controller input.
- [#5389](https://github.com/shadps4-emu/shadPS4/pull/5389): fix timezone/DST
  calculations and systemservice.cpp's hardcoded +120 minutes. Verify Windows
  UTC/local conversion in both summer and winter, including historical dates.
  This is correctness work; no effect on frame rate is established.

### 2. Renderer fixes with direct gaps in local code

1. Index buffer package:
   [#5278](https://github.com/shadps4-emu/shadPS4/pull/5278) ->
   [#5327](https://github.com/shadps4-emu/shadPS4/pull/5327) ->
   [#5358](https://github.com/shadps4-emu/shadPS4/pull/5358).
   Local Liverpool stores IndexBufferSize in num_indices; BindIndexBuffer uses
   that field for both draw count and buffer size, without the upstream capacity,
   mapped-range and null-base handling. Keep index capacity independently of
   individual draws, use wide arithmetic, clamp to mapped memory and preserve
   null base semantics. Do not import #5278 alone: it temporarily requires
   maintenance6, which #5327 makes optional with a zero-buffer fallback.
   Local recording goes through Scheduler::Stream, whereas upstream uses a raw
   command buffer. Extend the command stream for bindIndexBuffer2KHR if used;
   do not bypass the recorder. Preserve the small stream-buffer barrier path,
   repeated indirect draws and checked guest arguments. ClampRangeSize already
   exists locally, so no new memory manager interface is required.

2. Image copies:
   [#5299](https://github.com/shadps4-emu/shadPS4/pull/5299) ->
   [#5368](https://github.com/shadps4-emu/shadPS4/pull/5368).
   Local CopyImageWithBuffer still asserts equal layer counts and one mip.
   Port support for shared layers and every shared mip level. Verify staging
   offsets, alignment/capacity, image transitions and format reinterpretation,
   including the local depth/float backing-image reuse path.

3. Stencil/depth:
   [#5296](https://github.com/shadps4-emu/shadPS4/pull/5296).
   Local stencil_size is pitch * height and destinations of DepthStencilCopy
   do not call a shared AssociateStencil helper. Port both the size correction
   and association so copied stencil data follows the correct depth owner.
   Validate layers, tiling, shadows and depth/stencil consumers.

4. BC texture layout:
   [#5307](https://github.com/shadps4-emu/shadPS4/pull/5307).
   Local tables still have MAX_DIM_LOG2=11 and the matching lookup cap of 1024.
   Port the table and lookup condition together for supported 2048x2048 layouts.
   Validate the complete mip chain for both BC block sizes.

These are source-level correctness candidates. Their presence in a path used
by the emulator does not establish that any specific visible CUSA00004 defect
is caused by the missing fix.

### 3. Shader corrections as a separate wave

- Prioritize [#5348](https://github.com/shadps4-emu/shadPS4/pull/5348):
  the local prologue still gates vertex/instance unbiasing on SGPR availability.
  Add explicit indirect-draw state throughout runtime info and specialization.
  Check the local previous-pipeline and permutation caches and repeated-draw
  fast path. Preserve content-based variant names. Invalidate incompatible
  cached binaries; upstream moves ShaderBinaryVersion to 9 after #5342.
- [#5346](https://github.com/shadps4-emu/shadPS4/pull/5346): local CLAMP and
  LEGACY reciprocal/log instructions still share the ordinary translations.
  Preserve local GCN NaN handling while adding the distinct semantics.
- [#5342](https://github.com/shadps4-emu/shadPS4/pull/5342): expand fp64 detection;
  include cache invalidation, rather than only copying the opcode switch.
- [#5344](https://github.com/shadps4-emu/shadPS4/pull/5344) and
  [#5366](https://github.com/shadps4-emu/shadPS4/pull/5366): small missing
  gather/U64-undefined translations. Promote if shader logs show these cases.
- [#5352](https://github.com/shadps4-emu/shadPS4/pull/5352): additional descriptor
  rewrite pattern. Local StageSpecialization serializes buffers and runtime_info;
  this patch adds a BufferResource field. Audit metadata format compatibility,
  cache versions and specialization equality/hashing, not only compilation.

No shader capture or target-game opcode inventory was collected in this review.
Do not claim that the conditional shader additions fix this game's lighting.

## Already covered or unsuitable for a direct cherry-pick

- [#5316](https://github.com/shadps4-emu/shadPS4/pull/5316) advances the source
  pointer between physical backing runs. Local `54b34368` already advances
  both src and cursor in TryWriteBacking (memory.cpp:187 onward), without copying
  area maps. Preserve this local implementation.
- [#5317](https://github.com/shadps4-emu/shadPS4/pull/5317) addresses protections
  lost on a Windows mapping split. Local `43530466` already captures and restores
  protected runs. It is not byte-equivalent: upstream clips protections to each
  remapped region and asserts on query/restore failure; the local code can stop
  collecting on query failure and logs restore failure. Review those differences
  as focused hardening if needed, rather than replacing the local remap work.
- [#3396](https://github.com/shadps4-emu/shadPS4/pull/3396) is a major GC/readback
  change across 17 files, with tiled downloads, buffer flag/API changes,
  MaybeGpuDirty hashes, synchronous completion and actual backing allocation
  accounting. It overlaps local mirrors, page tracking, deferred destruction,
  copyback and recording. Do not import wholesale. A separate design/port must
  preserve the accepted slot-occupancy pressure check and demonstrate that no
  stale readback overwrites newer guest data. Its retry of image allocation
  without WITHIN_BUDGET is not a substitute for validating memory pressure.
- [#5046](https://github.com/shadps4-emu/shadPS4/pull/5046) adds CMask readback
  plus metadata ownership by image ID/UID. Worth a separate renderer port after
  smaller fixes, with metadata-address reuse, clear-state and stale-owner checks.
- Do not restore previously excluded deferred guest upload reads or the old
  shader variant shortcut as a side effect of updating upstream.
- Keep Windows-only automatic build/test policy. macOS/Rosetta and POSIX host
  fixes do not justify importing non-Windows CI or changing the local UI.

## Full intake matrix

"First renderer ports" means adapt and validate, not cherry-pick without review.
"Conditional" requires missing-API/opcode evidence from imports or logs.
"Later" is lower priority for the stated game and hardware.

| Upstream change | Decision | Reason |
| --- | --- | --- |
| [#5301](https://github.com/shadps4-emu/shadPS4/commit/144591e566814d8a74a649a5644262aa0ec1482d) Speed up game ID resolution by running a fast lookup for each install folder and skipping looking through game folders for other game dumps | Later | Startup game-ID lookup; lower priority than rendering and portable launch acceptance. |
| [#5296](https://github.com/shadps4-emu/shadPS4/commit/69b6041d76857392a44d50b0c17c32a5475bbefb) video_core: Link the stencil plane of DepthStencilCopy destinations | First renderer ports | Fix stencil plane sizing and associate DepthStencilCopy destinations. |
| [#5278](https://github.com/shadps4-emu/shadPS4/commit/0027696102f1ee67931a275a6320e1b8e10eb4de) amdgpu: Preserve index buffer capacity for indirect draws | First renderer ports | Preserve index capacity; port together with #5327 and #5358. |
| [#5299](https://github.com/shadps4-emu/shadPS4/commit/afde63182a380bb58953fb13e43c9deb44f7a346) renderer_vulkan: allow buffer copies between different layer counts | First renderer ports | Allow differing layer counts; port together with #5368. |
| [#5302](https://github.com/shadps4-emu/shadPS4/commit/de2817580a3821a3dabc3639b368dd7803b48204) devtools: Anchor the FPS counter at startup and refactor counter movement checks | Later | FPS overlay placement; no evidence it is needed for the target game. |
| [#5306](https://github.com/shadps4-emu/shadPS4/commit/0fe263a4760dfbfa973366890061749b4af0de97) fixed legancy network transfer issues | Later | Network transfer fixes; no target-game blocker demonstrated. |
| [#5317](https://github.com/shadps4-emu/shadPS4/commit/0c9ca525b8add53e62b3ccd9c9c2f6ef2ebabbfa) address_space: Restore protections after splitting a mapped region on Windows | Covered / compare | Local 43530466 already restores protections; review upstream clipping and failure handling separately. |
| [#5188](https://github.com/shadps4-emu/shadPS4/commit/149089be74676bdcf6c4abfa30b197954cf0d5e9) kernel: Implement POSIX file attribute and sync APIs | Conditional | POSIX file attribute/sync APIs; require evidence of target-game calls. |
| [#5207](https://github.com/shadps4-emu/shadPS4/commit/661d6fd0463a8ea5b441d3fcefd7d110a819c914) file_sys: Normalize guest paths and fix mount matching | Second wave | VFS normalization and mount matching; validate save and overlay paths. |
| [#5179](https://github.com/shadps4-emu/shadPS4/commit/30d82c9003480b991092279f7a10c2a3d2fe03b8) gnmdriver: Implement sceGnmSetGsRingSizes and sceGnmSetupMipStatsReport | Conditional | GS ring/mip report APIs; require evidence of use by CUSA00004 v1.07. |
| [#5326](https://github.com/shadps4-emu/shadPS4/commit/5cfd53250d3e57e23f02986b11d67481ece3cd5d) don't depend on console language always load cjk font | Later | CJK font loading; useful only for affected languages and missing glyphs. |
| [#5307](https://github.com/shadps4-emu/shadPS4/commit/e7929178af4bfc1bebb6365c9822d3234ef09098) tile: Expand table to 2048x2048 images | First renderer ports | Extend supported precomputed BC texture layouts through 2048x2048. |
| [#5327](https://github.com/shadps4-emu/shadPS4/commit/e9f2c54c207ad6d789d898b3a691aa4b34a59c96) renderer_vulkan: Bind a null index buffer instead of requiring maintenance6 | First renderer ports | Keep maintenance6 optional and provide a zero index buffer fallback. |
| [#5189](https://github.com/shadps4-emu/shadPS4/commit/437dc7eb8f6eeeb143ca0238366bb3aef9e95f03) core: Do not expand host mmap range during POSIX AddressSpace::Unmap | Skip for target | POSIX host mmap correction; Windows target is unaffected. |
| [#5330](https://github.com/shadps4-emu/shadPS4/commit/f1d5d5d63aa602f17d154464822ce09ff8c2b938) http: Redact credential headers in logs | Small fixes | Suppress credential headers in HTTP logs; matching unfiltered local logging remains. |
| [#5333](https://github.com/shadps4-emu/shadPS4/commit/81be949167d0060b08f26dc3e055a0b640d129c8) spilt np_handler to multiple files based on it purpose. | Defer | Large NP handler file split; conflicts with local trophies and adds little to this scope. |
| [#5335](https://github.com/shadps4-emu/shadPS4/commit/a8a70da595da2a96e0410309472ba4a7eb558144) http: Honor disable_https in HTTPS transport and private options | Conditional | HTTPS option behavior; inspect configured networking policy before taking it. |
| [#5316](https://github.com/shadps4-emu/shadPS4/commit/3eb39aac230dcc645fff1aecf388d365f67508dc) core: advance the source pointer for each backing run in TryWriteBacking | Covered | Local 54b34368 advances src and cursor across backing runs; do not replace it. |
| [#5308](https://github.com/shadps4-emu/shadPS4/commit/42bc3b408442f54285124926f2b987ccd67d244f) kernel: Implement private pthread barriers | Conditional | Private pthread barriers; require target-game API evidence. |
| [#5332](https://github.com/shadps4-emu/shadPS4/commit/06e813ff8c8e2a6d81b02cabfcc9543c3debf78e) kernel: Implement POSIX thread context, naming, file and process APIs | Conditional | Large POSIX/thread API expansion; import only demonstrated missing behavior. |
| [#5339](https://github.com/shadps4-emu/shadPS4/commit/c9018ee9635ee631520c96188c98660c78c1ee53) add emu settings = operator | Later | Settings assignment support; no target-game need established. |
| [#5340](https://github.com/shadps4-emu/shadPS4/commit/2c1961a270bdfb3a2727864ed9453a58a8715dfe) Fixes 33ms analog smoothing being accidentally applied to controller analog stick and triggers input | Small fixes | Take with #5377 to avoid analog input smoothing on physical sticks/triggers. |
| [#5337](https://github.com/shadps4-emu/shadPS4/commit/811bfcd7d17ed8ae975c477d9ff28abc744e1ca8) signaling-fix: always answer the offer | Later | Network signaling; no target-game blocker demonstrated. |
| [#5341](https://github.com/shadps4-emu/shadPS4/commit/443f022450f6857256e780daa3d5a14029a748f7) Implement sceGnmRequestFlipAndSubmitDone and sceGnmDrawIndirectCountMulti | Conditional | New GNM flip/indirect-count commands; upstream motivation is another game. |
| [#5346](https://github.com/shadps4-emu/shadPS4/commit/1c2b8f97af7d408e27a4d2923c41cdc6e1af920c) Implement proper clamping and handling for V_RCP_CLAMP_F32, V_RSQ_CLAMP_F32, V_RSQ_LEGACY_F32, V_LOG_CLAMP_F32 | Shader wave | Correct CLAMP/LEGACY ALU semantics; preserve local NaN handling and validate outputs. |
| [#5345](https://github.com/shadps4-emu/shadPS4/commit/2319a36986265440bbc6394e599296d96e74e3f2) Implement sceGnmComputeWaitSemaphore | Conditional | GNM compute semaphore; upstream motivation is HITMAN 3. |
| [#5342](https://github.com/shadps4-emu/shadPS4/commit/b08fd9bb41d78584e14b0f9b230635dc29be8d0b) shader_recompiler: Detect fp64 usage from instruction types | Shader wave | Detect fp64 operations correctly; include shader binary invalidation. |
| [#5344](https://github.com/shadps4-emu/shadPS4/commit/3a9f57265d28975658f1ca941daa5c879c7a74bd) shader_recompiler: Implement IMAGE_GATHER4_C_L | Shader wave | Handle IMAGE_GATHER4_C_L; no target-game occurrence demonstrated. |
| [#5348](https://github.com/shadps4-emu/shadPS4/commit/643c7997a5a0dfcb57959363b575b57a6257aa30) translate: Unbias vertex and instance ids in every indirect draw | High-value, separate port | Unbias IDs for all indirect draws; integrate cache/repeated-draw behavior and invalidate old shader binaries. |
| [#5352](https://github.com/shadps4-emu/shadPS4/commit/8bafaa5aca9b76f551ab2ea44d83dac73af00057) recompiler: Handle another sharp patching pattern | Shader wave | Additional descriptor patch pattern; audit serialized BufferResource layout before importing. |
| [#5046](https://github.com/shadps4-emu/shadPS4/commit/995e37e4e77ea9f3ec69367f9ec00867201ca191) Read CMask metadata | Separate renderer project | CMask readback and metadata owner lifetime tracking; touches local cache/readback behavior. |
| [#5323](https://github.com/shadps4-emu/shadPS4/commit/9901cfe6618eeea53a22932504f8b208f8386191) signindialog: basic error returns | Conditional | Sign-in error behavior; no target-game blocker demonstrated. |
| [#5354](https://github.com/shadps4-emu/shadPS4/commit/e0a466753a1aacbc8db8253be685bf7ab4d9daae) added matching delay | Later | Network matching delay; no target-game blocker demonstrated. |
| [#5360](https://github.com/shadps4-emu/shadPS4/commit/0ae50a4b09b5db547d014a41fe023927f258aff2) Removed the signaling_info setting as it is no longer in use. | Later | Remove unused signaling setting only when updating corresponding network code. |
| [#5361](https://github.com/shadps4-emu/shadPS4/commit/b72489d8c24e63fc56a29fe2c90120ab768a210d) added new notifications | Later | Network notifications; retain local UI. |
| [#5358](https://github.com/shadps4-emu/shadPS4/commit/23c41333822fe8eca4c609b43119180af63ae4ac) renderer_vulkan: Handle null index base address in BindIndexBuffer | First renderer ports | Null index base must remain null even when index_offset is nonzero. |
| [#5372](https://github.com/shadps4-emu/shadPS4/commit/7295d120b61c499cb309521ff1f5b898c5d62051) Update AGENTS.md | Skip as code import | Repository contribution rules are not emulator behavior; local instructions govern. |
| [#5370](https://github.com/shadps4-emu/shadPS4/commit/f47bbd5d6e9f49d3fd11cb4fd50533a835976a08) core: log SIGABRT signals on POSIX | Skip for target | POSIX SIGABRT diagnostics; Windows target is unaffected. |
| [529ceb32](https://github.com/shadps4-emu/shadPS4/commit/529ceb32f5546b820588f194b903cc39d08015fe) tagged 0.20.0 | Skip marker | Release/version marker only. |
| [fe06e920](https://github.com/shadps4-emu/shadPS4/commit/fe06e920967236d0b79b33d087f0de97ff2cb6cd) started 0.20.1 WIP | Skip marker | Release/version marker only. |
| [#3396](https://github.com/shadps4-emu/shadPS4/commit/e6faa2e3b6794a2fa79a709352ddfccfaa817ed1) video_core: garbage collector (part 2) | Separate renderer project | GC/readback redesign; preserve slot-pressure correction and reconcile worker/synchronization. |
| [#5192](https://github.com/shadps4-emu/shadPS4/commit/124328bcd37cebd4ae2be7d755bd44f1d7b49469) kernel: Implement I/O event queue APIs with Core::Net integration | Conditional | I/O event queues with networking integration; broad scope without target evidence. |
| [#5377](https://github.com/shadps4-emu/shadPS4/commit/c20cc3371b7ab0c978b23b1d9fb6f1c355672c1a) Properly check where an input came from for digital->analog input smoothing | Small fixes | Propagate actual analog origin through bindings; take with #5340. |
| [#5373](https://github.com/shadps4-emu/shadPS4/commit/15abf68c9b52c4b04d094f2837719fdb871021f3) kernel: fail rmdir on non-empty directories with ENOTEMPTY | Small fixes | rmdir must reject nonempty directories rather than recursively delete contents. |
| [#5368](https://github.com/shadps4-emu/shadPS4/commit/b3d46e96f1a5eb108f2cf771ed75ddd8f521b4e4) vk_runtime: Copy every mip level in CopyImageWithBuffer | First renderer ports | Copy all shared mip levels, not only level zero; follows #5299. |
| [#5385](https://github.com/shadps4-emu/shadPS4/commit/7be8e97f55488685b949353d494d39a754745f6e) app_content: Implement sceAppContentTemporaryDataMount | Conditional | Temporary-data mount API; require target-game import/log evidence. |
| [#5386](https://github.com/shadps4-emu/shadPS4/commit/232fa4db181785beb99bb9de9756619d39faf153) kernel: Try lock without wait in timed mutex if deadline has passed | Small fixes | Expired timed-mutex deadline must still attempt a nonblocking lock on Windows. |
| [#5366](https://github.com/shadps4-emu/shadPS4/commit/ab1dd384dc8a20c7faa3766324a27763768c59a3) shader_recompiler: Emit undefined 64-bit integers | Shader wave | Emit OpUndef for U64 rather than abort; no target-game occurrence demonstrated. |
| [#5338](https://github.com/shadps4-emu/shadPS4/commit/805e12c0f620f30103c4eda2794217fb251b9dcb) usbd: Implement libSceUsbStorage HLE for virtual USB media access | Defer | Virtual USB storage is not required by the stated target. |
| [#5388](https://github.com/shadps4-emu/shadPS4/commit/5dad16928a8a2cd546d3e75acf51071ec0c9510d) allowing headers with surrounding whitespace | Later | INI header whitespace parsing; small utility improvement without target blocker. |
| [#5297](https://github.com/shadps4-emu/shadPS4/commit/314c45632ec9efc314fd6721775de2686bfe1119) cpu_patches: Work around Rosetta 2 mistranslating negated scalar compares | Skip for target | Rosetta 2 compare workaround; irrelevant to Windows AMD. |
| [#5389](https://github.com/shadps4-emu/shadPS4/commit/b2d7ec7d31f9ad9426db93afe079db8679b3e1e0) kernel, rtc: Fix timezone and DST calculation | Small fixes | Fix timezone/DST and hardcoded CEST; validate Windows winter/summer conversions. |
| [#5392](https://github.com/shadps4-emu/shadPS4/commit/5aa7ffa3f4f21bba827d7865ed8f69f98f993542) music: Implement libSceMusicPlayerService HLE | Defer | New music service HLE and bundled FLAC decoder; no demonstrated target need. |

## Validation before accepting ports

Use small commits and a build for each coherent package. Preserve the existing
baseline and run the Windows build/checks. For emulation behavior changes,
follow runtime/AGENTS.md and share appropriate OpenOrbis hardware cases;
do not add repository tests.

On CUSA00004 v1.07, check indexed/indirect geometry, particle-heavy combat,
Seattle lighting/shadows, transitions, depth/float copies, mipmapped textures,
save/load and input switching. Check recorder enabled/disabled paths when
changing command recording, and keep Vulkan validation runs separate from timing.
For GC, add a long-session memory-pressure run on the target NVIDIA hardware.

Any performance comparison must follow [BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md)
and record results in PERFORMANCE_LOG.md. This review ran no builds, gameplay
sessions or benchmarks and makes no FPS claims. No runtime sources were modified.
