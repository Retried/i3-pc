# Pending continuation

- New PC2 Release/LTO build and automatic packaging: check
  `runtime/Build/pc2-20261016/launch.json`, `inputs.json` and `status.json` once at
  the next prompt. They record the actual PID/start time, source SHAs/configuration
  and logs. Missing status plus a dead process is interrupted/unknown. Do not
  start a duplicate or edit its sources while it is running. Intended output:
  `packages/i3-pc-PC2-20261016.zip`; the older W1 package remains available.
- Only this AMD/NVIDIA PC is available (user reconfirmed).
  The local Khronos-layer prerequisite check is blocked before game launch.
  External acceptance requires a second target PC and validation/reference
  checks; see [W_DELIVERY_20261016.md](W_DELIVERY_20261016.md)
  and [PC2_ACCEPTANCE.md](PC2_ACCEPTANCE.md). Do not mark these checks passed
  from a build result or title-control captures.
