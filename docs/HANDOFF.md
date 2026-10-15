# Continuation notes

Prepared on 2026-10-15 for the next project chat. This file records completed
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

The main commit containing this handoff pins runtime `1e2a7566` and includes the
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
  Its full Windows x64 emulator build and affected-file format check passed;
  cross-platform CI verification remains pending. See
  [CI_RUN_38805748119.md](CI_RUN_38805748119.md).
- The 44 inherited clang-format findings remain. Do not disable the check or
  perform a repository-wide formatting sweep without a task that calls for it.
- W1 portable Windows build and packaging remains planned; the scripts still
  contain machine-specific paths. Local build workarounds are not a portable
  build implementation.
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
