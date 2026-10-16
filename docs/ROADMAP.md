# Priorities

Work only on the requested scope. W1-W4 are distinct from renderer priorities 1-7.

| Stage | Remaining acceptance/work |
| --- | --- |
| W1: Windows build/package | Second-PC launch and gameplay acceptance; commands in [W1_WINDOWS.md](W1_WINDOWS.md). |
| W2: NVIDIA Vulkan | Candidate Windows build and repeated NVIDIA title startups passed; validation-layer runs and target-version gameplay remain. See [W2_NVIDIA_VULKAN.md](W2_NVIDIA_VULKAN.md). |
| W3: Benchmarks | Portable runner and local cold/warm control measurements implemented. Second PC and representative scenes remain; see [W3_BENCHMARKS.md](W3_BENCHMARKS.md). |
| W4: CPU/draw calls | Local CPU profile and direct-draw A/B recorded in [W4_CPU_DRAWS.md](W4_CPU_DRAWS.md). Representative gameplay, priority-2 isolation and second-PC validation remain. |

Renderer priority 2 is implemented; gameplay and measurements remain unverified.
Priority 1 remains an unapplied experimental patch.
Read the relevant section of [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md)
only when planning renderer work. Pending execution state is in [HANDOFF.md](HANDOFF.md).
