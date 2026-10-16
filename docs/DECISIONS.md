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
Provenance and validation are in [CI_RUN_38766554875.md](CI_RUN_38766554875.md).

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
not alter GPU synchronization or rendering. See
[CI_RUN_38805748119.md](CI_RUN_38805748119.md) for the failed run and validation.

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
