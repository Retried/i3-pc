# i3-pc Development Rules

## Target

- Windows x86-64.
- AMD Ryzen CPU.
- NVIDIA GPU with Vulkan.
- inFAMOUS Second Son CUSA00004 v1.07.

## Requirements

- Preserve game compatibility and rendering correctness.
- Do not remove existing optimizations without evidence.
- Avoid unrelated refactoring.
- Keep changes small and reviewable.
- Never claim FPS improvements without benchmarks.
- Verify completed builds and report pending builds and untested runtime behavior explicitly.
- Do not use Polish characters in scripts or comments.

## Workflow

- Read `docs/ROADMAP.md` for project priorities.
- Read `docs/HANDOFF.md` when continuing work from another chat.
- Use `docs/BENCHMARK_PROTOCOL.md` for performance tests.
- Record important design decisions in `docs/DECISIONS.md`.
- Record measured performance changes in `docs/PERFORMANCE_LOG.md`.

## Non-blocking build verification

- At the start of the next user prompt, check builds and CI runs recorded as
  pending in `docs/HANDOFF.md` before starting another build of the same revision.
- Launch long local builds in a detached, hidden process with persistent stdout,
  stderr and an exit-status file. Do not use an in-memory background job that
  disappears when the shell exits. For CI, record the run URL and commit SHA.
- Do not wait for compilation or repeatedly poll it during the current response.
  Complete independent work, record the pending result, and return to the user.
  Wait only when the user explicitly requests waiting for that build.
- Record the source revision and dirty state, exact command, configuration,
  process ID (when local), log/status paths and remaining checks in `docs/HANDOFF.md`.
- On the next prompt, inspect the exit code and final logs. If still running,
  keep it pending and continue independent work; do not launch a duplicate.
  Treat a missing status file and a dead process as interrupted/unknown, not PASS.
- Build success requires a successful exit and the expected executable. Packaging
  requires matching build metadata; do not package an incomplete candidate.
- Publishing an authorized source change may precede build completion. Label its
  validation pending and follow up on failures at the next prompt. Never describe
  a started build, configuration-only check or old build as validation of new code.
- Automated emulator artifact builds target Windows only. Linux/macOS artifact
  builds are opt-in manual checks; preserve existing cross-platform C++ tests.

## Repository layout

These documentation paths are relative to this top-level repository, including
when working inside the `runtime` Git submodule. The main repository contains
scripts and documentation; emulator sources are in `runtime` on the fork's
`runtime` branch. Also read `runtime/AGENTS.md` before editing runtime sources.
