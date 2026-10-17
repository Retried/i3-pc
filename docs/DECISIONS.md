# Design decisions

## 2026-10-15: Repository and documentation layout

The main repository holds scripts and project documentation. Emulator source is
the `runtime` submodule, with its URL pointing to `Retried/i3-pc` and its tracking
branch named `runtime`. Publish a runtime commit before publishing a main commit
that pins it. Documentation paths in the top-level `AGENTS.md` refer to the main
repository even when editing the submodule.

## 2026-10-15: Conservative incremental pipeline caching

Renderer priority 2 caches the register-derived render state and the previous
shader-variant lookup. Shader parameters, SRT memory, specializations and fetch
shaders still refresh for each draw or dispatch. The draw change mask alone
cannot account for guest-memory changes. Shader matching retains its resource
presence mask and existing fallback order; the on-disk cache format is unchanged.

The implementation is in runtime commit `9a719c45`. Windows build verification
does not establish a gameplay or performance improvement. Details and remaining
validation are in [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md).

## 2026-10-15: CI portability and bounded cleanup

Keep `__rdtsc()` on x86-64. Select `<intrin.h>` for MSVC/clang-cl and
`<x86intrin.h>` for other x86 compilers instead of changing the counter or adding
fences. Restrict formatting to the files covered by the fix; report inherited
findings rather than disabling CI or reformatting the repository.

REUSE copyright annotations for the 11 reported files use the recorded Git
author `i3-pc-port` and year 2026. Preserve their original GPL-2.0-or-later
declarations and list the exact paths in `runtime/REUSE.toml`.
The original CI evidence is
[run 38766554875](https://github.com/Retried/i3-pc/actions/runs/38766554875).

## 2026-10-15: Separate emulator and test builds

The current CMake configuration with `ENABLE_TESTS=ON` does not create the
emulator target. Validate the test configuration and the full emulator build
separately. Preserve existing tests and workflow checks, and report exclusions
and skips explicitly. Neither build nor test success replaces target-GPU or
gameplay validation.

## 2026-10-15: Explicit Python interpreter for the LTO script

`build-lto.bat` accepts `PYTHON3_EXECUTABLE` as an optional environment override,
checks that it runs Python 3, and passes it to CMake as `Python3_EXECUTABLE`.
Without the override, CMake keeps its normal interpreter discovery. Do not commit
a developer-specific Python installation path. For example, in PowerShell:

```powershell
$env:PYTHON3_EXECUTABLE = 'C:\Path\To\Python\python.exe'
.\build-lto.bat
```

Release/LTO configuration and target listing passed with Python 3.12.14 on
Windows x64. This check did not compile or run the LTO emulator. A CPU model
string containing Radeon 780M during configuration does not identify the Vulkan
device selected by the emulator at launch.

## 2026-10-15: Platform-specific freeze-log CPU timing

Preserve the Windows `GetThreadTimes` path and use POSIX
`clock_gettime(CLOCK_THREAD_CPUTIME_ID)` on Linux and macOS for the renderer's
freeze-log counter. Both return microseconds to the existing diagnostics.
Retain the previous counter if the OS query fails. This portability fix does
not alter GPU synchronization or rendering. The original failure is recorded in
[run 38805748119](https://github.com/Retried/i3-pc/actions/runs/38805748119);
the subsequent full build/test matrix passed in
[run 38812901885](https://github.com/Retried/i3-pc/actions/runs/38812901885).

## 2026-10-15: W1 build and package boundaries

Keep Windows orchestration in the wrapper repository. Discover Visual Studio
with vswhere and initialize its x64 host/target environment; select one x64 LLVM
installation consistently for CMake, font compilation, linker and builtins.
Use separate normal/LTO build directories and preserve explicit Python overrides.
Configuration is checked on every build instead of trusting a configured.ok file.

Package an explicit allowlist, not the live dist directory, which can contain
private saves, settings and game-derived assets. Refuse existing output paths,
record source/build provenance and file hashes, inspect imported dependencies,
and document system runtime requirements. A local CLI smoke test does not prove
NVIDIA compatibility, gameplay correctness or second-PC portability. See
[W1_WINDOWS.md](W1_WINDOWS.md) for usage and acceptance criteria.

## 2026-10-16: Windows artifacts and deferred build checks

Per user request, push/PR/default manual CI builds emulator artifacts for Windows
only. macOS, Linux Clang and Linux GCC emulator jobs require the manual
build_non_windows input. Cross-platform unit tests and existing checks remain.
The upstream release gate stays unchanged, but depends only on Windows artifacts.

## 2026-10-16: W1 package from existing CI artifact

Reuse the successful Windows CI executable for the exact clean runtime revision
instead of launching another build. Check the downloaded artifact archive against
GitHub's SHA-256 digest, preserve its executable bytes, and apply the existing
package allowlist and dependency inspection. Reconstruct missing build metadata
from CI evidence with an explicit origin and run/job/artifact identifiers;
distinguish the wrapper packaging revision from the compiled runtime revision.
Do not invent an exact build timestamp. Verify the extracted ZIP and CLI with
developer tools absent from PATH. Second-PC gameplay remains a separate
acceptance requirement. See [W1_PACKAGE_20261016.md](W1_PACKAGE_20261016.md).

## 2026-10-16: W2 diagnostics and validation boundaries

Retain existing NVIDIA shader adaptations and upload/readback synchronization.
Add bounded startup diagnostics and stop initialization after a failed device
creation, rather than continuing with an invalid device. Record actual feature
values and limits already used by the renderer; distinguish requested validation
from an explicitly enabled layer. Keep the standalone capability collector
read-only with respect to drivers, game data and emulator settings.

The observed NVIDIA/AMD capabilities do not justify speculative fallbacks or
removing existing optimizations. The inherited FP32 atomic min/max fallback's
two side effects require a separate behavior investigation with hardware cases;
startup success does not validate it. Preserve the active build's source snapshot.
Treat APP_VER and VERSION as distinct metadata: the local 01.00 application
could not establish acceptance for the requested 1.07 update without inspecting
the merged dump's provenance; the later local metadata repair is recorded in
[APP_VERSION_REPAIR_20261016.md](APP_VERSION_REPAIR_20261016.md). Keep capability
inventory, baseline smoke, candidate validation and performance claims separate.
Evidence and remaining acceptance: [W2_NVIDIA_VULKAN.md](W2_NVIDIA_VULKAN.md).

Long builds run in detached hidden processes with persistent logs and exit
status. The next user prompt checks the previous results; the current response
does not wait or repeatedly poll. Pending builds are not passing builds and
must not be used as evidence for package correctness or performance.

## 2026-10-16: Selective merge of runtime snapshot 01201155

Merge the runtime snapshot referenced by wrapper commit 6d2a7388, retaining our
shader specialization checks and synchronous upload copies. Accept the sampler
limit clamp and occupancy-aware image collection, correcting the pressure-relax
condition to consider remaining image slots. Publish the existing audio-only
formatting separately. See [UPSTREAM_6D2A7388.md](UPSTREAM_6D2A7388.md) for scope,
rejected paths, correctness evidence and validation limits. Do not infer a
performance win from source inspection. Prepare changes outside the source tree
of pending local builds and defer checkout synchronization until they finish.

## 2026-10-16: Windows tests and compact continuation context

Per user request, C++ test CI now targets Windows only; non-Windows emulator
artifacts remain manual opt-in. This supersedes the earlier cross-platform-test
policy. Fix formatting with clang-format 19 rather than weakening its check.
Keep recurring context split by purpose: AGENTS contains rules, ROADMAP contains
priorities, HANDOFF contains unresolved operational state. Store build provenance
in launch records and retain historical implementation detail in Git/reports,
not in instructions loaded every prompt.

## 2026-10-16: AMD CPU and NVIDIA GPU target; local merged metadata repair

Future build/run/validation work targets AMD CPUs and NVIDIA Vulkan GPUs only.
Do not schedule AMD/Intel GPU or Intel CPU compatibility or benchmark runs.
Keep inherited cross-vendor renderer paths; the target restriction does not
justify removing them. Restrict detailed diagnostic capabilities to the NVIDIA
device selected from enumeration, without relying on a fixed adapter index.

Correct the corroborated local merged CUSA00004 dump's stale APP_VER in its SFO
with a backup and one-byte verified write. Preserve VERSION, executable/assets
and the original package. Keep the emulator's normal APP_VER parsing; do not
add a VERSION override or title-specific version hack. This fixes identification
and does not install an update or establish full gameplay correctness.
Evidence and recovery: [APP_VERSION_REPAIR_20261016.md](APP_VERSION_REPAIR_20261016.md).

## 2026-10-16: W3 capture boundaries and W4 evidence

Reuse bench.sh, the runtime frame-interval recorder, perfsample.ps1 and the
existing stack sampler. Isolate every run's user data and freeze the executable,
seed and harness instead of deleting or replacing live saves. Define cold/warm
at the emulator-cache level; NVIDIA driver cache is uncontrolled. Report raw
data, percentile/low methods and repeat variation explicitly; missing counters
remain unavailable. Keep whole-card GPU load separate from per-process CPU/RAM
and unavailable GPU frame timing.

Only one target PC and opening autosaves are available. A static title or
cinematic measurement cannot establish a heavy-gameplay improvement. Use the
existing fast-path switch for a same-binary A/B before accepting any new renderer
change. Do not infer effectiveness of priority-2 commit 9a719c45 from a different
fast-path switch, or adopt the push-descriptor patch based on inspection alone.
Profiling is separate from timing and accounts for ASLR. The existing sampler
resets counts every ten seconds; snapshots are independent intervals and must
not be subtracted as cumulative totals. Stack scans are approximate, not an
exclusive time breakdown.
Method and commands: [W3_BENCHMARKS.md](W3_BENCHMARKS.md).

## 2026-10-16: release handoff and bounded cleanup

Separate delivered W1-W4 tooling/local evidence from unperformed external
acceptance. Removing implementation milestones from the checklist does not turn
missing second-PC or Vulkan validation checks into
passing results. Use one explicit release-acceptance list and a durable report.
Historical upstream investigation items are excluded from this delivery scope;
do not carry them into the current implementation checklist.

Start the new PC2 build only after source publication, in a new directory, with
a detached hidden worker and persistent launch/source/configuration/log/status
records. Package automatically only after matching executable metadata, verify
package and ZIP file hashes, and retain the old executable and package. Require
clean source at launch and an unchanged source state at build completion.

Acceptance tools run only on AMD/NVIDIA, verify CUSA00004 APP_VER 01.07, isolate
user data and distinguish blocked layer prerequisites from actual validation.
Keep core/synchronization, GPU-assisted validation and performance runs separate.
Use .NET hashing rather than depending on Get-FileHash module availability in
Windows PowerShell 5.1. Do not install an SDK or change global layer registration.

Clean only verified generated intermediates of a completed local build, with no
active compiler/build process, checked workspace-contained targets and no reparse
points. Retain artifacts, source dependencies, old packages, saves, metadata
repair backups and raw measurement evidence. Record removed sizes and verify
preserved artifact hashes.

## 2026-10-16: roadmap item 1 correctness ports

Port the input pair together and propagate actual binding origin. Preserve the
local resting-pad drift filter and keyboard smoothing; idle analog presence
must not disable digital smoothing. An analog return to center remains direct,
and changing source mode at an unchanged value must reach the controller.

Use Windows dynamic timezone APIs and per-year standard bias for time conversion,
rather than today's DST flag, a hardcoded hour or a hardcoded +120 minutes.
Share the kernel offset result with system service and use the supplied RTC date
for conversion/formatting. Keep the guest ABI field layout intact. Ambiguous
local-time policy still requires console evidence.

Port details, validation and OpenOrbis hardware cases:
[ROADMAP1_CORRECTNESS_20261016.md](ROADMAP1_CORRECTNESS_20261016.md).

## 2026-10-16: index buffer capacity and optional Vulkan features

Port #5278, #5327 and #5358 as one package. Preserve IndexBufferSize separately
from direct draw counts and keep null guest bases null after offsets. Use wide
byte arithmetic, cap to the existing u32 buffer-cache API before narrowing and
align the result to complete indices. Opt into strict mapped-range clamping
for indices while retaining the existing small-range fast path for other users.

Query and enable maintenance5/6 only with their feature and extension. Record
explicit-size binds through CommandStream, retain the legacy bind path and use
a tracked zero buffer when null index binds are unavailable. Preserve streamed
index-buffer reuse, its barrier exemption, checked arguments and draw fast paths;
include capacity in repeated-indirect reuse.

Build workers retain durable detached execution. At the user's request, agent
build output must appear in the integrated bottom Terminal panel, verified by
read_thread_terminal; an execution output card alone is insufficient. Closing
the viewer leaves the build running.

Evidence, limitations and OpenOrbis reference cases:
[ROADMAP2_INDEX_BUFFERS_20261016.md](ROADMAP2_INDEX_BUFFERS_20261016.md).

## 2026-10-16: shared layer/mip copies and staging capacity

Port #5299 and #5368 together. Build one aligned region layout for all shared
mips/layers and request staging capacity from that layout instead of assuming
128 MB. Add the pool allocation's base offset to each region, verify capacity
and require source/destination packed byte sizes to agree. Use 64-bit footprint
arithmetic with rounded block counts and the copied depth/stencil plane format.
Preserve the depth/float parked-twin reuse path and the existing multisample paths.

Keep image transitions and the intermediate copy barrier. Include earlier reads
when checking a staging write, and track the staging read/write range afterward.
Do not remove synchronization or bypass the command recorder.

The user now permits separate visible build consoles and prohibits desktop
control. Supersede the earlier bottom-terminal requirement: use the native
Start-Process console launcher, with durable worker/viewer launch records and
logs. Do not use UI automation or injected input to attach a build viewer.

Evidence and pending OpenOrbis/gameplay cases:
[ROADMAP3_IMAGE_COPIES_20261016.md](ROADMAP3_IMAGE_COPIES_20261016.md).

## 2026-10-16: stencil plane size and copy-destination ownership

Port all three parts of #5296 together. Derive stencil bytes from the finalized
depth guest footprint divided by depth bytes per sample, retaining layers,
samples and tiling/alignment padding. Share the existing AssociateStencil logic
between target binding and DepthStencilCopy destinations, using the write
stencil address and current depth ID/UID. Retain owner-lifetime checks, cache
registration/generation invalidation, copy synchronization and local optimizations.

Do not expand this small port into alias/GC redesign or copy-aspect policy
changes without separate evidence. Hardware cases cover plane growth, ownership
reuse, layers, padding, shadow consumers and depth/stencil readback.
Evidence: [ROADMAP4_STENCIL_20261016.md](ROADMAP4_STENCIL_20261016.md).

## 2026-10-16: shared BC layout capacity

Port #5307 by sharing MAX_DIM_LOG2 between both constexpr table generators and
the lookup guard. Twelve entries include 2048 at index 11 while excluding 4096.
Retain all other eligibility restrictions, the generic layout calculation and
local descriptor memoization. No serialized cache layout changes are required.
Inspect the compiler-evaluated table values for both BC block widths; rendering
acceptance remains separate. Evidence:
[ROADMAP5_BC_LAYOUT_20261016.md](ROADMAP5_BC_LAYOUT_20261016.md).

## 2026-10-16: indirect shader variants, finite clamps and fp64

Include explicit indirect-draw state in software vertex RuntimeInfo and retain
its equality/serialization in local content-based variants. Keep the previous
pipeline and repeated-indirect shortcuts; their existing dependency checks
must still distinguish direct/indirect switches. Increment ShaderBinaryVersion
to 9 and ShaderMetaVersion to 7: inserting a raw RuntimeInfo field changes
serialized meaning even if structure size stays constant. Reject old metadata
before deserializing specializations; leave PipelineKeyVersion unchanged.

Use ordered comparison/selects for translation-local finite clamping. The local
shared FPClamp uses numeric NMin/NMax and would erase NaN here; keep that helper
and other instructions unchanged. Port the final explicit fp64 opcode switch.
Leave gather/U64/descriptor-pattern ports conditional without target-game
evidence; a future descriptor port needs another resource serialization audit.
Evidence and pending OpenOrbis cases:
[ROADMAP6_SHADERS_20261016.md](ROADMAP6_SHADERS_20261016.md).

## 2026-10-17: guest path normalization and virtual root

Normalize guest slash-separated components before mount and permission selection,
independently of Windows filesystem parsing. Reject Windows drive/stream/backslash
syntax on Windows; do not rewrite host-configured paths. Keep boundary matching
and select the longest mount. Normalize mount registration/unmount as well;
replace changed registrations after backend construction and clear the host
case-search cache. Preserve overlay order and archive backends.

Keep guest root virtual: synthesize directory access and stat without returning
the host drive root from GetHostPath. Share root-entry snapshots between directory
APIs and invoke callbacks outside the mount lock. NormalDirectory must own the
normalized path. Do not extend this lexical port into symlink or CWD emulation.
Evidence and pending OpenOrbis/save cases:
[ROADMAP7_VFS_20261017.md](ROADMAP7_VFS_20261017.md).

## 2026-10-17: integrate push-descriptor filtering

The user explicitly requested roadmap item 8 as a normal project change,
superseding the earlier recommendation to leave the patch unapplied pending
measurements. Integrate it into CommandStream, default enabled, and remove the
standalone patch. Keep rendering/performance acceptance separate; no FPS claim
or benchmark acceptance follows from this source decision.

Use independent graphics/compute set-0 caches and compare relevant descriptor
values, retaining fixed capacity and whole-batch fallback for unsupported cases.
Filter on the producer before deep copying to the worker. Invalidate on new
sessions even for reused handles, target/layout changes, ordinary sets, opaque
callbacks and direct command-buffer access. Direct handles must be reacquired
after stream calls. Preserve barriers and resource preparation.

Add resource-reclamation notices consumed by the producer, and invalidate on
shader replacement before pipeline-layout handles can be recycled. Deferred
callbacks publish an atomic notice rather than mutate producer cache arrays.
Keep same-binary cache disable and optional cumulative diagnostics for coverage,
hit runs and invalidation reasons; do not version unrelated shader cache data.
Evidence and pending OpenOrbis/A-B cases:
[ROADMAP8_PUSH_DESCRIPTORS_20261017.md](ROADMAP8_PUSH_DESCRIPTORS_20261017.md).

## 2026-10-17: Xbox prompt style through the existing texture pack

Reuse the existing prompt sets and texture upload path. Persist the live Controls
selection in the existing force.txt, preserving legacy values and defaulting to
Auto. Recognize Xbox devices explicitly; unknown controllers retain original
artwork unless the user forces Xbox. Observe device activity before menu input
is consumed without changing input processing or guest pad mappings.

Generate sparse procedural patches for documented atlas cells instead of shipping
or depending on a copied game atlas. Preserve touchpad/motion and unverified
artwork, including D-pad and separate glyph textures. Do not guess their cells or
map touchpad press to View. Keep normal unknown-glyph GPU readback disabled unless
diagnostic capture is requested. Track style application at cache invalidation,
not at an individual image upload, so one image cannot suppress other refreshes.
Coverage, file format, evidence and pending validation:
[XBOX_PROMPTS_20261017.md](XBOX_PROMPTS_20261017.md).

## 2026-10-17: remove only provably redundant GPU polling

Item 9's initial diagnostic run has no usable exact timeline/submit profile:
the seed entered the opening gesture scene and the Release/LTO executable has
no matching PDB. Preserve those limitations rather than interpreting export
symbol names or the frame counter labelled submits as API measurements.

Implement state-proven reductions: skip callback polls for empty/unsubmitted
fronts and consume known-complete ticks; let the existing pool-pressure and
submitted-callback paths perform refreshes instead of refreshing unconditionally
at submit; publish each Vulkan counter sample with a monotonic CAS loop without
driver requery. Keep all waits, spin behavior and immediate readback/signal paths.
Use a per-scheduler periodic budget reset by actual submits, retaining the
512-call limit and forced boundaries. Do not add a poll timer or enlarge batches
from this incomplete profile. Add optional exact atomic counters and a
same-binary legacy switch, with matched worker-off/on diagnostic and timing
matrices. No descriptor-cache or draw-filter benefit is credited to item 9.
Evidence and pending reference cases:
[ROADMAP9_GPU_SUBMISSIONS_20261017.md](ROADMAP9_GPU_SUBMISSIONS_20261017.md).

## 2026-10-17: filter repeated recording commands on the producer

Keep the existing dynamic-state, render-scope, pipeline-selection and item-8
descriptor filters. Add transient exact-value comparisons before queue copies
for pipeline/index/legacy-vertex bindings and push constants; do not skip resource
preparation, barriers or draws. Track graphics/compute pipelines separately and
retain sized/legacy index distinctions. Keep only the most recent complete
vertex/constant call, avoiding assumptions about partial-write dependencies.

Invalidate graphics pipeline binding on every named dynamic setter because a
rebind can reapply static pipeline state. Leave dynamic vertex size/stride binds
unfiltered and invalidate the legacy vertex tuple on that API. Clear all new
state for sessions/targets/direct/opaque recording and resource/layout lifetime
changes. Consume the reclamation notice once but invalidate both command and
descriptor caches, so no cache misses the event.

Use independent optional per-family producer and per-chunk worker wall-time
counters, with cache off/on and worker off/on matrices. Exclude diagnostic runs
from performance summaries even if the stack sampler is not requested. Keep
descriptor settings constant; total replay/copy savings are not all item-10
savings. Baseline legacy counters cannot provide exact worker replay cost.
Source integration is distinct from measured performance acceptance; see
[ROADMAP10_COMMAND_FILTERING_20261017.md](ROADMAP10_COMMAND_FILTERING_20261017.md).

## 2026-10-17: bind readbacks to mapping and CPU-consumption lifetime

Item 11 starts from a producer-copy-CPU dependency model. A virtual address being
valid does not identify the original mapping, and GPU completion does not mean
that a CPU callback has consumed its staging bytes. Add per-backing-page mapping
generations and transient readback tokens; validate and commit under the mapping
lock. Use expected-word CAS for known snapshots so a CPU write racing between
the old comparison and memcpy is checked again, including physical aliases.
Retain scratch reuse and stretch coalescing. Value ABA remains a stated limit;
do not infer full write-generation tracking from this change.

Keep existing waits, copy barriers, callbacks and frame-lead limits. Protect both
urgent and ordinary mirror ring reservations until CPU consumption. Waiting only
for GPU completion would still allow the ring to overwrite bytes before a
pending callback reads them. Unknown dispatch snapshots cannot prove safe
asynchronous merging; use the existing synchronous path instead of silently
skipping an urgent result or copying whole stale bytes in the background.
Record this correctness fallback separately from any performance claim.

Port CMask #5046 separately with owner ID/UID, address replacement and clear-mask
preservation. Reject stale owners and unsupported encodings rather than filling
zero from an engaged optional. Do not import #3396, change GC pressure thresholds
or remove waits without equivalence evidence. Image GC ordering, alias watcher
counts and deferred staging release still require item 12's separate audit.
Details and pending OpenOrbis/reference workloads:
[ROADMAP11_READBACK_20261017.md](ROADMAP11_READBACK_20261017.md) and
[ROADMAP11_CMASK_20261017.md](ROADMAP11_CMASK_20261017.md).

## 2026-10-17: complete GC image commits before address reuse

Adapt #3396 locally instead of merging its buffer API, tracker and hash-based
ownership policy. Image readback completes on the producer before eviction;
retain mapping/expected-byte guards and hold staging through CPU consumption.
This removes image staging release from the priority thread and prevents a
delayed image callback from overwriting a later producer. Preserve ordinary
deferred Vulkan destruction and cache lifetime invalidation.

Retain GPU-valid images with uncertain overlapping buffer producers, including
direct aliases, rather than treating equal hashes as ownership evidence. Keep
the existing dirty-image eviction policy and clear uncertainty on normal uploads;
copies propagate it. Notify buffer uploads after readback without clearing
neighboring GPU ranges or local mirrors. Conservative retention can limit pressure
recovery and requires explicit long-run acceptance.

Use all mip/layer layouts and existing tilers with guest-seeded padding, guarded
dispatch and transfer/compute access tracking. Retain unsupported layouts. Charge
actual VMA bytes until destruction, including parked/alternate/deferred images;
keep device heap pressure and the local slot trigger. Bound candidate scans and
evictions, fix LRU callback termination and admit younger images under increased
pressure while retaining the current tick. Do not add over-budget allocation
retry as a substitute for recovery evidence. Rationale and reference workloads:
[ROADMAP12_GC_READBACK_20261017.md](ROADMAP12_GC_READBACK_20261017.md).

## 2026-10-17: separate saved-cache restoration from speculative PSO preparation

Item-13 cold/warm diagnostics confirmed existing compatible-cache restoration:
382 restored pipelines, no warm graphics compilation, and five newly encountered
compute programs absent from the seed. Do not guess their shader specializations
or enable unmeasured speculative work by default. Keep content-based variants and
all existing shader/PSO lookups. Initialize the shared Vulkan cache before WarmUp.

Add an opt-in, bounded TriangleList/TriangleStrip counterpart prewarmer using
compatible restored shaders, complete keys and owned fetch/serialization data.
Exclude geometry/tessellation/patch/no-fragment and pointer-dependent recipes;
record no guest commands or speculative persistent entries. Save a prepared key
only after an actual exact-key guest request. Separate restoration, preparation,
first-use shader/PSO timing and actual hits so unused work remains visible as cost.
Limits and pending acceptance: [ROADMAP13_PIPELINE_PREWARM_20261017.md](ROADMAP13_PIPELINE_PREWARM_20261017.md).

Per the user's request, syntax-check launches retain hidden workers and durable
logs but no longer open the additional Checking console. Full build launches
retain the visible log viewer required by AGENTS.md.

## 2026-10-17: standalone input profile and menu ownership

Import the bundled profile through the runtime's active input-path resolver.
Migrate only a stock unified default with no existing per-game profile; do not
overwrite custom bindings or reverse an explicit later unified selection. The
PC bindings editor uses the same resolver. Xbox gesture substitutes use ordinary
chords and the existing motion/touch emulation rather than guest/game patches.

Open PC settings directly from the start screen: waiting for native game Options
requires save loading and cannot serve startup configuration. Route SDL menu
navigation before capture and exclude NoNavInputs display windows from keyboard
and gamepad capture, while preserving explicit OSK/IME handling and input releases.
Evidence and limits: [INPUT_FIX_20261017.md](INPUT_FIX_20261017.md).
