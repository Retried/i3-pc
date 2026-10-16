# Priorities

Work only on the requested scope. W1-W4 are distinct from renderer priorities 1-7.

| Stage | Remaining acceptance/work |
| --- | --- |
| W1: Windows build/package | Second-PC launch and gameplay acceptance; commands in [W1_WINDOWS.md](W1_WINDOWS.md). |
| W2: NVIDIA Vulkan | Audit/diagnostics implemented; candidate build, validation-layer runs and target-version gameplay remain. See [W2_NVIDIA_VULKAN.md](W2_NVIDIA_VULKAN.md). |
| W3: Benchmarks | Portable, repeatable two-PC measurements and comparison. |
| W4: CPU/draw calls | Profile first; validate existing optimizations against a baseline. |

Renderer priority 2 is implemented; gameplay and measurements remain unverified.
Priority 1 remains an unapplied experimental patch.
Read the relevant section of [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md)
only when planning renderer work. Pending execution state is in [HANDOFF.md](HANDOFF.md).
