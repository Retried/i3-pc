# i3-pc rules

Target: Windows x86-64, AMD Ryzen, NVIDIA Vulkan, CUSA00004 v1.07.

- Build and runtime validation targets are AMD CPUs with NVIDIA Vulkan GPUs only.
  Do not schedule AMD/Intel GPU or Intel CPU builds, launches, benchmarks or
  compatibility checks. Keep existing renderer portability paths intact.

- Preserve rendering correctness and existing optimizations; require evidence for removal.
- Keep changes focused. No FPS claims without benchmarks. Scripts/comments use ASCII.
- Read `docs/ROADMAP.md` for priorities and `docs/HANDOFF.md` for pending work.
  Read linked detail only when relevant to the task; do not reload unchanged rules.
- Runtime sources are in the `runtime` submodule; read its AGENTS.md before editing.
  Documentation paths here are relative to this wrapper repository.
- Before performance tests use `docs/BENCHMARK_PROTOCOL.md`; record measurements in
  `docs/PERFORMANCE_LOG.md` and non-obvious design decisions in `docs/DECISIONS.md`.
- Keep HANDOFF limited to pending checks, blockers and context not recoverable from
  code/Git. Link durable reports and launch records instead of copying them.
  Remove resolved entries; do not repeat rules, commit history or file inventories.

## Builds

- At the next prompt, check recorded pending local/CI results once. Do not wait or
  repeatedly poll builds unless explicitly asked; do not start duplicate jobs.
- Launch long local builds detached and hidden, with persistent stdout/stderr and
  exit status. Store command, PID/start time, configuration, source SHA/dirty state
  in a launch record; put its path in HANDOFF. For CI record run URL and source SHA.
- Missing status plus dead process means interrupted/unknown. Success requires
  exit 0 and the expected executable; packaging also requires matching metadata.
- Do not edit sources used by running builds. Authorized source publication may
  precede completion, but report pending validation and untested runtime behavior.
- Automatic emulator builds and C++ tests target Windows. Linux/macOS emulator
  artifacts remain manual opt-in; do not reintroduce non-Windows tests unrequested.
