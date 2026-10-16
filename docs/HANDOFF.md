# Pending continuation

- W1 second-PC acceptance is pending for `packages/i3-pc-W1-b499ca7-20261016.zip`.
  Identity, passed local verification, provenance/log locations and remaining
  checks: [W1_PACKAGE_20261016.md](W1_PACKAGE_20261016.md).
- Check the detached W2 Windows build and automatic NVIDIA candidate startup
  smokes once at the next prompt. Launch/source snapshot:
  `runtime/Build/w2-nvidia-20261016/build.launch.json`; final pipeline status:
  `build-and-smoke.status.json` in the same directory. Keep its runtime source fixed.
  The pending AMD follow-up is guarded to skip without launching.
- Check [CI 38896616489](https://github.com/Retried/i3-pc/actions/runs/38896616489)
  for runtime `f88d3b6f331272ce854bda5875c11386b180f94f` once at the next prompt.
- W2 acceptance blockers and the inherited FP32 atomic-fallback finding are in
  [W2_NVIDIA_VULKAN.md](W2_NVIDIA_VULKAN.md). The Khronos validation layer is absent.
  Local APP_VER repair and NVIDIA confirmation are recorded in
  [APP_VERSION_REPAIR_20261016.md](APP_VERSION_REPAIR_20261016.md). Baseline title/intro smokes
  do not validate the candidate or target-version gameplay. Long-session,
  second-PC, readback and performance validation remain pending.
- Official shadPS4 intake candidates and validation requirements are in
  [UPSTREAM_SHADPS4_20261016.md](UPSTREAM_SHADPS4_20261016.md). No candidate ports
  have been applied. The report also records the completed Windows CI checks.
