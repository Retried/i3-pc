# Continuation notes

Updated on 2026-10-16 for the next project chat. This file records completed
work and remaining checks; it does not authorize implementing another stage.

## Start here

1. Read the top-level [AGENTS.md](../AGENTS.md) and
   [runtime/AGENTS.md](../runtime/AGENTS.md).
2. Read [ROADMAP.md](ROADMAP.md), then the relevant section of
   [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md).
3. Check `git status` in both repositories before editing. The local main
   repository uses branch `main`; the submodule uses branch `runtime`, tracking
   `origin/runtime`. Both origins point to `https://github.com/Retried/i3-pc.git`.
4. Check the latest runtime GitHub Actions run before deciding which CI fixes
   remain. Local validation below is not a result from a new remote run.

The target remains Windows x86-64, AMD Ryzen, NVIDIA Vulkan and CUSA00004 v1.07.
Do not trade rendering correctness or stability for FPS.

## Published runtime changes

- `9a719c45`: renderer priority 2, incremental register-derived pipeline state
  and a cache of the previous shader-variant lookup. Shader-visible guest memory
  still refreshes. Built on Windows, but not benchmarked or validated in-game.
- `1e2a7566b34b831250a16a471811c1e7bc54ecbb`: CI portability and metadata fix.
  The rasterizer selects the intrinsic header for MSVC/clang-cl versus GCC/Clang
  x86-64 without changing the `__rdtsc()` calls. Only the affected C++ files were
  formatted. REUSE annotations record verified author/year metadata for 11 files.

The current main checkout pins runtime `f921cf04` and includes the
development rules, expanded roadmap, benchmark protocol, decisions and results
log. Read [DECISIONS.md](DECISIONS.md) before changing the cache or build workflow.

## Completed local validation

- Full emulator Windows x64 build: PASS, including linking `shadps4.exe`, using
  clang-cl 19.1.5 and RelWithDebInfo.
- Separate existing test build: PASS. CTest used the same `-E GcnTest` selection
  as the workflow: 507 tests, zero failures, three self-skips. See the exact skips
  in [the CI report](CI_RUN_38766554875.md).
- MSVC and clang-cl x64 intrinsic compilation probes: PASS. Clang freestanding
  Linux x86-64 and macOS x86-64 object probes: PASS. Each emits `rdtsc`.
- REUSE 6.2.0: PASS, 1081/1081 files with license and copyright metadata.
- clang-format 19.1.7: the affected rasterizer and pipeline-cache files pass.
  All 46 findings in the analyzed run existed in the parent commit; fixing the
  two affected files leaves 44 inherited findings listed in the CI report.
- No full local GCC/Linux or macOS build, NVIDIA hardware test, gameplay test
  or performance benchmark was performed. Do not label these as passing.

## Remaining work

- Run [38805748119](https://github.com/Retried/i3-pc/actions/runs/38805748119)
  completed: Windows emulator, all three C++ test jobs and REUSE passed.
  Linux GCC, Linux Clang and macOS emulator builds exposed an additional
  unguarded Windows thread-time API in the rasterizer. Published runtime `340d9afa`
  preserves Windows timing and uses POSIX thread CPU timing elsewhere.
  Its full Windows x64 emulator build and affected-file format check passed.
  Follow-up CI [38812901885](https://github.com/Retried/i3-pc/actions/runs/38812901885)
  completed successfully: all four emulator builds, all three C++ test jobs and
  REUSE passed; clang-format retained the same 44 inherited failures.
  See [CI_RUN_38812901885.md](CI_RUN_38812901885.md).
- The 44 inherited clang-format findings remain. Do not disable the check or
  perform a repository-wide formatting sweep without a task that calls for it.
- W1 now has shared Windows tool discovery, normal/LTO wrappers and allowlisted
  portable packaging. See [W1_WINDOWS.md](W1_WINDOWS.md) for commands and validation.
  Second-PC launch and gameplay acceptance remain pending.
- W2 NVIDIA validation, W3 repeatable two-PC measurements and W4 further
  measured CPU optimization remain as described in the roadmap.
- Renderer priority 1 is an unapplied experimental patch, preserved at
  [patches/priority1-push-descriptor-cache.patch](patches/priority1-push-descriptor-cache.patch).
  Read its review and verify applicability before any future application.

## Local artifacts and future validation

Ignored files under `runtime/Build/` include `ci-configure.log`, `ci-build.log`,
`ci-ctest.log`, `ci-emulator-configure.log`, `ci-emulator-build.log`, the
`ci-windows-x64/` build and isolated `ci-tools/` tooling. Helper scripts there
are local, contain machine-specific tool paths and are not committed. They may
not exist in a fresh clone. Their command setup is not a replacement for W1.

`ENABLE_TESTS=ON` does not create the emulator target in the current CMake setup;
check the test and emulator configurations separately. Keep the existing tests
and CI checks intact. Use [BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md) before
measuring and record only actual measured changes in
[PERFORMANCE_LOG.md](PERFORMANCE_LOG.md).

## Current continuation: W1 and non-blocking builds

The previous fresh normal and LTO builds both linked shadps4.exe successfully.
The old LTO script process then failed to write metadata because Get-FileHash was
unavailable. The current script uses .NET SHA-256; the incremental normal build
and an allowlisted package passed. `packages/W1 validation incremental.zip` is
that earlier validation artifact, not a package of the later dirty checkout.

The current user requested Windows-only automatic emulator artifact builds.
The workflow now gates macOS, Linux Clang and Linux GCC builds behind manual
workflow_dispatch with build_non_windows=true (default false). Cross-platform
C++ tests remain enabled. The upstream-only release condition is preserved;
its dependencies now include only Windows and get-info.

The top-level and runtime AGENTS.md now require recording long builds without
waiting. Check the pending build records below on the next prompt; do not start
duplicate builds or claim success before reading their final status and logs.

A separate pre-existing local formatting change in
`runtime/src/core/libraries/audio/sdl_audio_out.cpp` was discovered on resume.
It is preserved and excluded from the requested CI/AGENTS publication. Local
refresh builds include that dirty file and must not be confused with clean CI.

The user explicitly confirmed publication to https://github.com/Retried/i3-pc.git
on 2026-10-16. Runtime `f921cf04f458d455751ac4e9db3385e9d00204d8` publishes the
workflow and AGENTS.md policy changes. The main W1 commit pins that revision.
The unrelated audio formatting change remains local and must not be staged.

### Pending local builds: check on the next prompt

Started on 2026-10-16 in hidden detached processes, without waiting:

| Variant | PID | Entry command from repository root |
| --- | --- | --- |
| RelWithDebInfo | 25964 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File runtime/Build/w1-resume-20261016/run.ps1 -Variant normal` |
| Release/LTO | 23328 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File runtime/Build/w1-resume-20261016/run.ps1 -Variant lto` |

Source: main `8cf172f2eebe5e2aa9c123d5ecf9c1471dc90730` plus local W1/docs/rules
changes; runtime `340d9afac55cdc4267a197ef1c96aacd7ff03072` plus local workflow,
AGENTS.md and the separate audio-formatting change. These are dirty local builds.

Records live in ignored `runtime/Build/w1-resume-20261016/`:

- `normal.started.json`, `lto.started.json`: exact launch commands, PIDs, revisions.
- `normal.stdout.log`, `normal.stderr.log`, `lto.stdout.log`, `lto.stderr.log`.
- `normal.status.json`, `lto.status.json`: created when the wrapper finishes;
  require exitCode=0 and verify matching build-info.json/executable hashes.
- Expected outputs: `runtime/Build/w1-x64-Clang-RelWithDebInfo/shadps4.exe` and
  `runtime/Build/w1-x64-Clang-Release-lto/shadps4.exe`, with build-info.json beside each.

The helper invokes tools/build-windows.ps1 with -Jobs 3 and the local explicit
Python interpreter; -Configuration Release -Lto is added for the LTO variant.
Do not start duplicate jobs. If a status file is absent, verify the PID/start time
from the started record; a dead process without status means interrupted/unknown.
After success, package the desired matching build and smoke-test the new package.
At the publication prompt, both recorded processes were still running and no
status files existed; no duplicate jobs were started and no completion was claimed.
The source refs were advanced for publication while these builds were running.
Use the launch records for their original revisions and final metadata/logs for
their completion state; they are not substitutes for clean CI on the published ref.

### Pending CI: check on the next prompt

[Run 38860588943](https://github.com/Retried/i3-pc/actions/runs/38860588943)
was queued for runtime `f921cf04f458d455751ac4e9db3385e9d00204d8` after publication.
On the next prompt, verify Windows build and test/check results and confirm that
the three non-Windows emulator jobs were skipped on this push. Do not wait or
repeatedly poll during the publication response. The older successful run
38812901885 does not validate the new workflow changes.
