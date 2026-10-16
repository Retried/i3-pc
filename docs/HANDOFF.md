# Pending continuation

- W1 second-PC acceptance is pending for `packages/i3-pc-W1-b499ca7-20261016.zip`.
  Identity, passed local verification, provenance/log locations and remaining
  checks: [W1_PACKAGE_20261016.md](W1_PACKAGE_20261016.md).
- Check [CI 38896616489](https://github.com/Retried/i3-pc/actions/runs/38896616489)
  for runtime `f88d3b6f331272ce854bda5875c11386b180f94f` once at the next prompt.
  Last single check during W3 preparation: in progress. Do not start a duplicate.
- W2 acceptance blockers and the inherited FP32 atomic-fallback finding are in
  [W2_NVIDIA_VULKAN.md](W2_NVIDIA_VULKAN.md). The Khronos validation layer is absent.
  Local APP_VER repair and NVIDIA confirmation are recorded in
  [APP_VERSION_REPAIR_20261016.md](APP_VERSION_REPAIR_20261016.md). Candidate title-control
  startups passed; target-version gameplay, long-session and readback validation
  remain pending.
- W3/W4 have only one available AMD/NVIDIA PC and 0-percent opening autosaves.
  Obtain city/combat/resource-churn fixtures and a second target PC before full
  acceptance. Local evidence and reproduction: [W3_BENCHMARKS.md](W3_BENCHMARKS.md),
  [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md), [W4_CPU_DRAWS.md](W4_CPU_DRAWS.md).
  Existing direct-draw switching does not isolate priority-2 commit `9a719c45`;
  a separately built matching baseline is still needed for that comparison.
- Official shadPS4 intake candidates and validation requirements are in
  [UPSTREAM_SHADPS4_20261016.md](UPSTREAM_SHADPS4_20261016.md). No candidate ports
  have been applied. The report also records the completed Windows CI checks.
