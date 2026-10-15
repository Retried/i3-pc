# Project roadmap

The detailed plan and implementation history are maintained in
[PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md). Read it before selecting work;
this page is the entry point, not a second copy of the full plan.
For the current checkout, validation results and continuation notes, read
[HANDOFF.md](HANDOFF.md).

## Development stages

| Stage | Scope | Current status |
| --- | --- | --- |
| W1 | Portable Windows build, toolchain discovery, packaging and launch | Planned; current scripts contain machine-specific paths. |
| W2 | NVIDIA Vulkan compatibility and diagnostics | Basic device diagnostics exist; target hardware validation remains pending. |
| W3 | Repeatable benchmarks and profiling on two PCs | Existing scripts need portability, metadata and comparison improvements. |
| W4 | CPU and draw-call optimization guided by measurements | Existing optimizations need validation against a baseline on both PCs. |

W1-W4 are distinct from the renderer priorities numbered 1-7 in the detailed
plan. Renderer priority 2 has a source implementation and a successful Windows
build; game validation and performance measurements remain pending. The
priority 1 push-descriptor patch remains experimental and unapplied.

CI portability fixes and their validation are documented in
[CI_RUN_38766554875.md](CI_RUN_38766554875.md). The remaining 44 inherited
clang-format findings are listed there; they are not new optimization work.

Work on the stage requested by the user. A roadmap entry alone does not authorize
implementation of every stage. Use [BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md)
for measurements, [DECISIONS.md](DECISIONS.md) for design decisions and
[PERFORMANCE_LOG.md](PERFORMANCE_LOG.md) for measured outcomes.
