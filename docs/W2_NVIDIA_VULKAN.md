# W2: NVIDIA Vulkan audit and diagnostics (2026-10-16)

## Status and scope

The capability audit, diagnostic collector and focused startup diagnostics are
implemented. The candidate Windows build finished with exit 0 and matching
executable metadata. W3 repeated title-control runs of that candidate also exited
0 on NVIDIA with APP_VER 01.07. W2 acceptance remains open because the Khronos
validation layer is unavailable locally and gameplay coverage is incomplete.
The local merged dump's
stale APP_VER was repaired and startup now reports 01.07; see
[APP_VERSION_REPAIR_20261016.md](APP_VERSION_REPAIR_20261016.md). Short baseline
runs do not establish gameplay correctness or long-session stability.

The current build/run/validation target is AMD CPUs with NVIDIA GPUs only.
AMD/Intel GPU and Intel CPU testing is outside scope. AMD observations below
are historical results collected before this instruction, not a future matrix.

Baseline runtime: `b499ca72329ab179c365ca695570d6d79e57a998`, existing CI
Release/LTO artifact with clang-cl 20.1.8. Executable SHA-256:
`FB9AF84C34D149D3F2DD0BC5A6C0F612D547E0E8CB0FF169AAEE611236D9E81A`.
Wrapper HEAD at preparation: `c0b51c2dc6a4e0924a99e1038be03ceae6e4a1fb`.
The baseline executable does not include the new W2 source changes.

No renderer optimization, shader fallback, upload scheduling or guest readback
algorithm was replaced. Subsequent W3/W4 local work is recorded in
[W3_BENCHMARKS.md](W3_BENCHMARKS.md) and [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md).
The priority-1 patch remains unapplied.

## Hardware and capabilities observed

Windows 11 Pro, version `10.0.26200`, build `26200`; AMD Ryzen 5 7640HS,
6 cores/12 logical processors. Vulkan loader reports `1.4.341`.

| Property | NVIDIA GeForce RTX 4050 Laptop GPU | AMD Radeon 760M |
| --- | --- | --- |
| Vulkan API | 1.4.351 | 1.4.344 |
| Driver reported by Vulkan | NVIDIA 617.42 / 617.42.0.0 | AMD proprietary 26.5.2 (LLPC) / 2.0.388 |
| Windows driver version | 32.0.16.1742 | 32.0.31007.5012 |
| Subgroup size | 32 | 64 (supported range 32-64) |
| Storage-buffer offset alignment | 16 bytes | 4 bytes |
| Noncoherent atom size | 64 bytes | 128 bytes |
| Compute shared memory limit | 49,152 bytes | 32,768 bytes |
| Max push descriptors | 32 | 32 |
| Required device extensions and robustness2 bits | Present | Present |
| Timeline semaphore, buffer address, synchronization2, dynamic rendering | Supported | Supported |
| VK_EXT_shader_atomic_float2 | Unavailable | Available |
| Khronos validation layer | Not enumerated | Not enumerated |

The required extensions are swapchain, push descriptor, vertex attribute divisor
and robustness2. Required robustness2 bits are robustBufferAccess2,
robustImageAccess2 and nullDescriptor. The queried divisor feature is also true
on both devices. Optional feature bits currently requested with literal true in
CreateDevice (custom border colors, depth clip, dynamic vertex input,
barycentrics, provoking vertex, maintenance5/8, image min LOD and maximal
reconvergence) were checked against the raw inventory on these two GPUs.
Feedback-loop dynamic state is absent on AMD; the existing paired-extension
selection excludes that path there. This is not evidence for other GPU/driver
combinations. Extension availability alone is insufficient to establish support
for every feature bit; see [vkCreateDevice](https://docs.vulkan.org/refpages/latest/refpages/source/vkCreateDevice.html).

Seven layers are installed, including RTSS, Optimus, AMD switchable graphics and
Steam layers. vulkaninfo emits an RTSS API-version warning. Existing implicit
layers and global driver/settings configuration were left as found.

## Code audit and changes

| Area | Finding and action |
| --- | --- |
| Instance/device setup | Existing GPU/vendor/driver/API and extension logs are retained. CreateDevice's false return was ignored by the windowed constructor; initialization now stops with a named error before querying further device state. |
| Core feature prerequisites | Timeline semaphore, buffer device address, synchronization2 and dynamic rendering are consumed by the existing semaphore, allocator, command stream and scheduler. Added explicit prerequisite assertions and one startup feature summary. Feature enablement remains the existing queried values. |
| Limits and queues | Added one startup log for push-descriptor limit, storage alignment, noncoherent atom size, shared memory and selected graphics queue family. It does not add per-draw logging. |
| Validation | Existing layer enumeration already reports unavailable requested layers. The new summary distinguishes a request from an explicitly enabled Khronos layer and labels core/sync/GPU settings as requested checks. It does not imply that an absent layer validated a run. |
| NVIDIA shader profile | Existing manual interpolation, LDS barriers, clip-distance emulation and buffer-offset policy are retained. One startup line reports the selected flags. NVIDIA's 16-byte storage alignment differs from AMD's 4-byte alignment and already selects the appropriate buffer-offset path. |
| Shader atomics | Native FP32 min/max capability is feature gated. NVIDIA uses the existing integer fallback; a correctness concern requiring follow-up is documented below. No speculative replacement was applied. |
| Synchronization | Reviewed timeline submission/waits and the command stream's synchronization2 barriers. Graphics and presentation use the selected family. Queue scheduling and command recording are unchanged. |
| GPU-to-CPU download | DownloadMemory retains Finish, mapped-memory invalidation and backing-memory writes in that order. Existing mirror readbacks additionally use bounded asynchronous batches, snapshots and urgent completion paths; these must not be described as universally synchronous. They were not modified. |
| Resource pressure | Existing image-slot pressure correction and collection limits remain. Long-session/VRAM-pressure correctness is unverified. Excluded upstream upload/shader paths remain excluded; see [UPSTREAM_6D2A7388.md](UPSTREAM_6D2A7388.md). |

Changed runtime functions are Instance's windowed constructor, Instance::CreateDevice,
CreateInstance, and PipelineCache's constructor in the three renderer_vulkan
translation units. The additive logs and initialization guard have low expected
regression risk; successful initialization should retain existing rendering
choices. Candidate compilation and title-control startup passed subsequently;
representative gameplay and Vulkan-layer validation remain pending.
The Vulkan 1.3 feature definitions are documented by
[Khronos](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceVulkan13Features.html).

### Existing atomic fallback concern

In `shader_recompiler/backend/spirv/emit_spirv_atomic.cpp`, the FP32 min/max
fallback emits both signed/unsigned integer atomics as arguments to OpSelect.
OpSelect selects a result; it does not conditionally execute those side effects.
For example, FMin with stored +1.0 and incoming +2.0 should leave +1.0 stored,
whereas executing both integer UMax and SMin stores +2.0. The source already
contains a FIXME about needing control flow.

This is a static correctness finding on a path relevant to the observed NVIDIA
capabilities, not a demonstrated failure in a CUSA00004 shader from these runs.
Before a separate behavior fix, establish which target shaders exercise it and
compare returned old values and final memory against OpenOrbis/PS4 cases:
positive/negative pairs, signed zero, infinity and NaN, for buffer and image
min/max; include contended atomics and a native-capability GPU comparison.
Keep the existing startup work's build source fixed while it runs. A shader
behavior patch requires separate validation; this audit does not claim the
fallback is correct or accept it based on successful startup.

## Completed baseline runs

All runs used an isolated executable directory, copied settings/saves, a hidden
SDL window and dummy audio. The originals under dist/user were not used as the
write destination. The existing SOTC_SCRIPT driver requested screenshots and a
clean quit. GPU selection was explicit (NVIDIA index 1, AMD index 0 in this
inventory); these indices must be rechecked on another PC.

| Run | Observed result | Exit |
| --- | --- | --- |
| baseline-nvidia | Black/loading frame followed by rendered title/Continue screen | 0 |
| baseline-amd | Black/loading frame followed by rendered title/Continue screen | 0 |
| gameplay-nvidia | Title transition, intro text, then rendered opening coastal scene with lighting/foliage | 0 |

The first two scripts quit at 65 seconds after first presentation; the third at
100 seconds. These are smoke-test durations, not performance measurements.
Selected screenshots were inspected. The NVIDIA opening scene has visible
geometry, foliage, sky and sunlight, but was not compared with PS4 reference
imagery. Combat, particle effects, free-roam input, save/load, scene changes,
readback stress and long sessions remain unchecked.

At the initial audit the game's SFO had TITLE_ID=CUSA00004, APP_VER=01.00 and VERSION=01.07.
The emulator log explicitly reports `App Version: 01.00`. VERSION=01.07 must not
be substituted for the APP_VER update acceptance requirement. During those
initial runs no game files or updates were modified or downloaded.

Those are the initial observations. A later comparison with the local merged
package, changeinfo and SDK metadata corroborated stale APP_VER in that dump;
the one-byte local metadata repair and NVIDIA startup verification are recorded
in [APP_VERSION_REPAIR_20261016.md](APP_VERSION_REPAIR_20261016.md). Earlier smoke
results are not retroactively promoted to full gameplay acceptance.

The three logs contain no matches for Critical, device-lost, assertion-failed or
VK_ERROR patterns. They do contain existing warnings/errors (including linker
stubs, buffer/rasterizer diagnostics and stencil state warnings). A pattern scan
is not proof of correct rendering. Validation was disabled, and no valid
Khronos core/synchronization/GPU-assisted run was performed.

## Reproduction and evidence

`tools/collect-vulkan-diagnostics.ps1` creates a new diagnostics directory and
records AMD CPU/NVIDIA GPU hardware/OS, NVIDIA Vulkan capabilities, selected environment variables,
wrapper/runtime revisions and dirty state, optional executable hash/build
metadata, and only explicitly supplied runtime logs. Missing data is null or
marked unavailable. Existing output directories are rejected. It never starts
the game or changes global driver configuration.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collect-vulkan-diagnostics.ps1 -OutputDirectory runtime/Build/my-vulkan-report -Executable "packages/i3-pc-W1-b499ca7-20261016/inFAMOUS Second Son.exe"
```

vulkaninfo must be installed or supplied with -VulkanInfoPath. The schema-2
collector uses --summary only to discover the NVIDIA index and available layers,
then writes --json=<NVIDIA index> to vulkan-capabilities.json. Detailed capability
collection targets NVIDIA only; Intel CPU and AMD/Intel GPU inventory is excluded.
-RuntimeLog accepts
explicit log paths. Logs may include local paths. The collector writes the full
capability report with vulkaninfo's own --output option; redirected full stdout
hung near completion in this environment. Those failed attempts remain as
diagnostic evidence; the final file-output invocation completed with exit 0,
reported unavailable validation and matched the executable's build metadata.
The collector passed in PowerShell 7 and Windows PowerShell 5.1, including
capability-probe exit 0, hardware/Git inventory, executable metadata/hash match
and correct reporting of the missing validation layer. Windows PowerShell's
process handle is retained so its exit code remains available. PowerShell parsing
and clang-format 19 validation passed. No repository tests were added.
The NVIDIA-only schema-2 collector also passed on Windows PowerShell 5.1, selecting
GPU index 1 and reporting only the AMD CPU and NVIDIA GPU as hardware targets.

Raw local evidence is under `runtime/Build/w2-nvidia-20261016/`:

- `diagnostics-file-output/diagnostics.json` and `vulkan-capabilities.txt`:
  successful collector output, plus the explicitly supplied NVIDIA startup log.
- `diagnostics-powershell5-fixed/`: successful Windows PowerShell 5.1 collection.
- `diagnostics-nvidia-only/`: successful schema-2 NVIDIA-only profile and the
  corrected-APP_VER NVIDIA log.
- `vulkan-summary.txt`, `vulkan-full.txt`: initial successful driver inventories.
- `baseline-nvidia/`, `baseline-amd/`, `gameplay-nvidia/`: run records, statuses,
  isolated user data, screenshots and complete logs.
- `source.patch` and `build.launch.json`: fixed candidate patch, file hashes,
  source revisions/dirty state, command, PID/start time and configuration.
- `build.stdout.log`, `build.stderr.log`: detached build/pipeline output.

The candidate pipeline was launched at 13:37 Warsaw time, PID 24528. It builds
Windows x64 RelWithDebInfo with clang-cl 19.1.5, LTO off, 3 workers, then verifies
the expected executable and build metadata and runs an isolated NVIDIA startup
smoke. Its original AMD follow-up is now guarded and records a skipped result
without launching an emulator, under the user's updated hardware policy.
`build.status.json` records build/metadata success; final pipeline status
is `build-and-smoke.status.json`. Candidate run directories are candidate-nvidia
and candidate-amd. Their source is the dirty W2 snapshot, not the baseline binary.
The W3 prompt checked build.status.json once: exit 0, expected executable present,
and matching build metadata. SHA-256:
`DC983DB65BE1F9585E183EA2D1F5B6F59C673728FC8E264A015500CA1F729EE0`.
Subsequent isolated W3 runs independently confirmed successful NVIDIA startup
and APP_VER 01.07 with this binary. The original pipeline's final smoke status
was not used as gameplay acceptance.

The startup source changes were published as runtime
`f88d3b6f331272ce854bda5875c11386b180f94f` while the local build was pending.
The launch record describes the same source files as a dirty patch over b499ca7;
their hashes were verified unchanged before publication. Metadata written at
build completion can name the newer commit, while the generated build revision
can still describe the original launch state. Neither publication nor that
revision change establishes a passing build.
[CI 38896616489](https://github.com/Retried/i3-pc/actions/runs/38896616489)
for f88d3b6f completed successfully, confirmed at the single delivery-prompt
check on 2026-10-16. The detached local build/smoke pipeline also records exit 0.

## Remaining acceptance

1. Check the newer PC2 release artifact and its actual second-PC acceptance;
   the f88d3b6f Windows CI result is already successful.
2. Use the corrected, corroborated CUSA00004 01.07 dump for target acceptance
   runs; retain the repair provenance.
3. Supply a compatible Khronos validation layer and run core/synchronization
   validation separately from GPU-assisted validation and all timing runs.
   Preserve layer version, explicit enabled-layer log and exact settings.
4. Validate opening/free roam, combat/particles, lighting/shadows, transitions,
   save/load and GPU-to-CPU readbacks on NVIDIA; compare representative images
   and behavior on the second AMD-CPU/NVIDIA-GPU PC.
5. Investigate the inherited FP32 atomic fallback with appropriate hardware
   cases before accepting any behavior change.
6. Run a long-session resource-pressure check. Record which GPUs, drivers and
   scenes were actually covered; other configurations remain unverified.

The original W2 audit did not measure performance. Subsequent local control
measurements belong to W3/W4 in [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md);
they do not establish a gameplay FPS improvement.
