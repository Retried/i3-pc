# Pending continuation

- PC2 Release/LTO build and automatic packaging: the latest 2026-10-16 check found
  final status `failed`, exit 1: source state changed during the build. Do not
  accept this artifact. Its rejected build directory has been removed; inspect
  the retained logs before deciding on a fresh launch. Records:
  `runtime/Build/pc2-20261016/launch.json`, `inputs.json` and `status.json`.
  Intended output:
  `packages/i3-pc-PC2-20261016.zip`; the older W1 package remains available.
- Generated files were removed from the retained W1 Release/LTO and W2 debug
  build directories. Reconfigure before another incremental build; executable,
  PDB and metadata hashes were preserved. Cleanup evidence:
  `runtime/Build/pc2-20261016/cleanup.json`.
- Only this AMD/NVIDIA PC is available (user reconfirmed).
  The local Khronos-layer prerequisite check is blocked before game launch.
  External acceptance requires a second target PC and validation/reference
  checks; see [W_DELIVERY_20261016.md](W_DELIVERY_20261016.md)
  and [PC2_ACCEPTANCE.md](PC2_ACCEPTANCE.md). Do not mark these checks passed
  from a build result or title-control captures.
