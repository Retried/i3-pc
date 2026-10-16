# W1: portable Windows build and packaging

## Audit and scope

The wrapper owns build and packaging scripts; runtime owns the emulator and
CMake presets. The old batch files hard-code a Visual Studio edition and LLVM
directory. `install.sh` hard-codes the checkout. CMake presets require 3.30,
Ninja and clang-cl; the emulator also needs the x64 MSVC/Windows SDK environment,
Python 3 and the matching Clang builtins library. Fonts use the compiler from
PATH, so explicit CMake paths and PATH must select the same x64 toolchain.

The profiler and renderer already expose the counters in the performance
roadmap. W1 does not change rendering, profiling or synchronization. Existing
`dist` contents include private saves and configuration: package only an explicit
allowlist into a new directory.

Scope: shared tool discovery and build entry point in `tools/build-windows.ps1`,
small batch wrappers, relative developer installation, allowlisted packaging,
and build/second-PC instructions. No global environment changes or installation.

Validation: full Windows emulator build, optional LTO build, package contents and
dependencies, packaged executable smoke test. Second-PC gameplay remains a
manual acceptance requirement; W1 cannot be closed without that check.

## Build

Install Git, Python 3, and Visual Studio 2022/Build Tools with Desktop development
with C++, a Windows SDK, C++ Clang tools for Windows and C++ CMake tools. Use
CMake 3.30 or newer, Ninja, and a complete x64 LLVM installation including
compiler-rt and lld-link. The locally available Clang 19.1.5 is the initial
validation toolchain; other versions need their own validation.

From a 64-bit Windows shell at the repository root:

```powershell
.\build.bat
.\build-lto.bat
```

The default builds use separate directories under `runtime/Build`:
`w1-x64-Clang-RelWithDebInfo` and `w1-x64-Clang-Release-lto`. Configuration is
checked on every run; `-Fresh` resets CMake configuration, not source files.
`-Jobs 4` limits build concurrency. `-ConfigureOnly` checks configuration without
building; it does not establish LTO or emulator success. Full builds are required.

Optional overrides are `-VisualStudioPath`, `-LlvmPath` (the x64 LLVM bin
directory), `-PythonExecutable`, and `-BuildDirectory`. Python also accepts the
existing `PYTHON3_EXECUTABLE` environment variable. Paths may contain spaces.
For example:

```powershell
.\build.bat -PythonExecutable 'C:\Tools\Python\python.exe' -Jobs 4
```

VS installation is discovered with vswhere. The selected VS bundled CMake,
Ninja and x64 LLVM are preferred, with PATH fallback for missing tools. A custom
LLVM path must include clang-cl, clang, lld-link and x64 compiler-rt builtins.
The script imports only a process-local x64 development environment. Missing
tools or unsuccessful configure/build commands return a nonzero exit code.
Initial configuration downloads CMake dependencies and needs network access.
Initialize source dependencies with `git submodule update --init --recursive`.

For agent-driven work, keep the worker detached with durable logs/exit status and
a HANDOFF.md entry, and always show its output in a visible console. The launcher
opens a separate console by default through tools/open-windows-build-console.ps1.
It records the viewer PID/command in console-launch.json and streams both durable
logs through tools/show-windows-build.ps1. The final result stays visible until
Enter is pressed. Closing the viewer leaves the build running.

The user authorized a separate console window and prohibited taking control of
the desktop: do not use UI automation, injected input or window activation for
builds. -Detach is only for explicit manual use. The next prompt checks the build
result once; a viewer streaming output does not require agent status polling.
The batch wrappers remain synchronous when run directly by a developer.

To display logs for a build launched separately (custom workers may use the
optional *File parameters):

```powershell
& .\tools\open-windows-build-console.ps1 -LaunchDirectory '.\runtime\Build\my-launch'
```

For the detached PC2 Release/LTO build and automatic verified package, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start-windows-build.ps1 -BuildDirectory runtime/Build/pc2-x64-Clang-Release-lto-20261016 -PackageDirectory packages/i3-pc-PC2-20261016 -LaunchDirectory runtime/Build/pc2-20261016 -Configuration Release -Lto -Jobs 3 -PythonExecutable 'C:/Tools/Python/python.exe'
```

Supply an existing Python path and new output paths. The launcher requires a
clean checkout and AMD/NVIDIA host, refuses overlapping builds/emulators, records
launch/source state and streams logs by default. The hidden worker writes persistent
stdout.log, stderr.log and status.json, then packages with acceptance tools and
checks executable/manifest/ZIP hashes. Only status complete/exitCode 0 with the
expected artifact confirms success; runtime behavior still needs acceptance.

## Package and launch

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package-windows.ps1
# For the optional LTO build:
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package-windows.ps1 -BuildDirectory runtime/Build/w1-x64-Clang-Release-lto
```

Each invocation creates a new folder and ZIP in ignored `packages/`. Existing
outputs are never overwritten. `-OutputDirectory` selects another new folder.
The script checks executable SHA-256 against build metadata, inspects imported
DLLs recursively using dumpbin, and fails on unresolved non-system dependencies.
`-DllDirectory` supplies additional dependency search directories; `-DumpbinPath`
selects a custom inspection tool. System DLLs are requirements, not redistributed.
Dynamic driver loading and actual Vulkan feature support still need runtime
validation; a dependency scan is not a GPU compatibility test.

The allowlist includes launcher scripts, the player guide, default bindings,
the freshly built executable, needed non-system DLLs, license and build metadata.
No `dist/user`, `game_path.txt`, game icons, glyphs, firmware or game data is copied.
Optional game icons use the executable icon when absent. `build-info.json`
records source revisions, working-tree changes, toolchain and executable hash;
`package-manifest.json` records package file hashes and dependency names.

On the target PC, extract to a writable directory. Requirements: Windows 10/11
x64, x86-64-v3 CPU (target AMD Ryzen), compatible Vulkan GPU/driver (target NVIDIA),
and Microsoft Visual C++ 2015-2022 x64 Redistributable. Build tools and Python are
not needed to play. Write your own game's absolute `eboot.bin` path into
`game_path.txt`, then run `Play.bat`. The program creates local settings and saves
under `user`. `Install.bat` optionally creates shortcuts.

## Second-PC acceptance

Record CPU, GPU, Windows and driver versions, package hash, and build-info.json.
Check `"inFAMOUS Second Son.exe" --help`, launch CUSA00004 v1.07, load a save,
verify keyboard/mouse, effects and scene transitions, then exit and relaunch to
check that settings and saves persist. Record failures and missing dependencies.
Gameplay and performance validation belong to W2/W3; no FPS claim follows from
this build or package work. Preserve the existing PC's saves before testing.

## Validation record (2026-10-16)

- Existing RelWithDebInfo build reconfigured and linked successfully through the
  new wrapper, with clang-cl 19.1.5 and Python 3.12.14. Build provenance emitted.
- Initial package generated in a path containing spaces. CLI `--help` passed
  with PATH restricted to Windows/System32 and Windows; no developer tools in PATH.
- ZIP inspection: 12 allowlisted files, no user data, game path, game icon or glyphs.
- Existing-output protection passed and preserved the ZIP hash. Missing Visual
  Studio, x86 compiler, missing Python, missing metadata and mismatched executable
  hash all returned nonzero status. PowerShell parsing and Bash syntax checks passed.
- Fresh RelWithDebInfo compilation and linking passed in `w1-build.log`.
- Fresh Release/LTO compilation and linking passed in `w1-lto-build.log`, but
  that older script process failed while writing metadata with Get-FileHash.
  The current script uses .NET SHA-256; its incremental validation already passed.
  Final normal/LTO wrapper refreshes completed with exit 0. Their source revisions
  predate the upstream merge/formatting; they do not validate current sources.
- Runtime CI 38812901885 completed successfully; all emulator builds and C++
  tests passed. The 44 inherited clang-format findings remain.
- No second-PC launch, game session, NVIDIA validation or benchmark has been run.

## Current second-PC package (2026-10-16)

The current package uses the existing successful Windows SDL artifact from
[CI 38862336590](https://github.com/Retried/i3-pc/actions/runs/38862336590),
runtime `b499ca72329ab179c365ca695570d6d79e57a998`. This is a Release/LTO build
with clang-cl 20.1.8 on `windows-2025-vs2026`, rather than the older local
Clang 19.1.5 build. No new build is required to package this artifact.

For this CI artifact, `build-info.json` is reconstructed from the artifact API,
workflow and job log. It records CI origin, run/job/artifact identifiers, archive
digest and executable hash. The wrapper revision and changes describe packaging
inputs; the runtime revision describes the compiled source. The exact build
completion timestamp is unavailable and is recorded as null; artifact creation
time is recorded separately. This does not claim a local wrapper build.

Package identity, verification results and the second-PC acceptance record are
tracked in [W1_PACKAGE_20261016.md](W1_PACKAGE_20261016.md). The second-PC check
above remains necessary before closing W1.
