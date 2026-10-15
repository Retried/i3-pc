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
- Verify builds and report untested runtime behavior.
- Do not use Polish characters in scripts or comments.

## Workflow

- Read `docs/ROADMAP.md` for project priorities.
- Read `docs/HANDOFF.md` when continuing work from another chat.
- Use `docs/BENCHMARK_PROTOCOL.md` for performance tests.
- Record important design decisions in `docs/DECISIONS.md`.
- Record measured performance changes in `docs/PERFORMANCE_LOG.md`.

## Repository layout

These documentation paths are relative to this top-level repository, including
when working inside the `runtime` Git submodule. The main repository contains
scripts and documentation; emulator sources are in `runtime` on the fork's
`runtime` branch. Also read `runtime/AGENTS.md` before editing runtime sources.
