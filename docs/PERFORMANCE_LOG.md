# Measured performance changes

No new optimization benchmarks have been performed in the work recorded by this
chat. Pipeline-cache changes have build validation, not a measured FPS result.
Do not enter predicted benefits, build times or unit-test counts as gameplay
performance improvements.

Historical project measurements are available in [BENCHMARK.md](BENCHMARK.md).
They were collected on the configuration stated in that document, including an
AMD GPU; they are not new measurements on the target NVIDIA configurations and
do not validate subsequent optimizations.

## Required entry format

For each measured change, follow [BENCHMARK_PROTOCOL.md](BENCHMARK_PROTOCOL.md)
and record:

- Date, change description and baseline/candidate main and runtime commit IDs.
- Machine and driver configuration, build settings and local patches.
- Scene, route, emulator settings and cache state.
- Raw CSV/JSON locations and number of runs on each PC.
- Baseline and candidate average FPS, 1% low, frametime distribution and variation.
- Correctness and stability results, regressions and untested configurations.
- Conclusion supported by the measurements; record inconclusive results as such.

There are currently no new measured-change entries to add.
