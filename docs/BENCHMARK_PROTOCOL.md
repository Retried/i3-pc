# Benchmark protocol

Target Windows x86-64, AMD Ryzen and NVIDIA Vulkan with CUSA00004 v1.07.
Both PCs must use an AMD CPU and NVIDIA GPU. AMD/Intel GPUs and Intel CPUs are
outside the build/run/benchmark target matrix.
Validate correctness before interpreting a performance result. A successful
build or unit-test run is not evidence of correct gameplay or improved FPS.

## Record the conditions

- Main and runtime commit IDs, local patches and dirty working-tree state.
- Build type, compiler, linker and LTO settings.
- Machine identifier, CPU, GPU, RAM, OS and driver versions.
- Emulator settings, environment variables, resolution, frame cap and VSync.
- Save, scene, camera or route, warm-up duration and measurement duration.
- Shader and pipeline cache state; cold and warm cache are separate series.

## Run the comparison

1. Preserve the baseline and candidate builds with identical settings.
2. Use the same scene and route, including a heavy panorama, a scene with frequent
   resource changes and a light control scene. Back up saves and configuration.
3. Run each configuration 3-5 times on each of the two PCs, alternating A/B order.
   Do not compare cold-cache baseline runs with warm-cache candidate runs.
4. Save raw frametimes and available CPU/GPU statistics in CSV or JSON alongside
   the conditions. Mark unavailable measurements explicitly; do not use zero.
5. Report average FPS, 1% low, median and p95/p99 frametime, worst frame and
   variation between runs. Define 1% low consistently: 1000 divided by the mean
   of the slowest 1% of frame durations in milliseconds.
6. Compare image correctness, scene transitions, effects and stability as well
   as timing. Run Vulkan validation separately from performance measurements.

Accept an optimization only when the measured benefit exceeds normal variation
and no material correctness or control-scene regression is observed. Define
regression thresholds from the baseline rather than inventing an FPS target.
State which hardware, gameplay checks or long-running tests remain unverified.

Record actual results in [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md), including raw
data locations. Existing tools and optimization-specific counters are described
in [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md); extend those tools where
appropriate instead of duplicating them.
