# W1-W4 delivery and remaining release acceptance (2026-10-16)

Delivered implementation work is no longer repeated as W1-W4 implementation
goals in ROADMAP.md. Complete acceptance remains open: the user reconfirmed that
only this AMD/NVIDIA PC is available. Moving
milestones out of the implementation checklist does not mark unavailable checks
as passed. The remaining checks are explicit in ROADMAP.md and below.
Historical upstream investigation items are outside this delivery scope.

## Delivered work

| Stage | Delivered evidence | Remaining acceptance |
| --- | --- | --- |
| W1 | Windows build/package scripts, allowlisted ZIP, old package verified locally, new detached PC2 build/package launcher and packaged acceptance tools. | New Release/LTO build result and actual launch/gameplay on a second PC. |
| W2 | NVIDIA capabilities/startup audit, version-identification repair, successful local build/smokes and Windows CI. Isolated smoke/validation capture now distinguishes blocked layer prerequisites. | Khronos layer runs, release gameplay/readback/stability and hardware reference checks. |
| W3 | Portable provenance/frametime/telemetry tools, cold/warm repeats, explicit metrics and tested suite comparison. Six local control trials recorded. | Matching repeats on a second AMD/NVIDIA PC. |
| W4 | Separate CPU profile and six direct-draw A/B trials; retain the measured existing optimization. No speculative renderer changes. | Isolated priority-2 baseline comparison, validation and second-PC checks before accepting further changes. |

Detailed durable reports: [W1 package](W1_PACKAGE_20261016.md),
[W2](W2_NVIDIA_VULKAN.md), [W3](W3_BENCHMARKS.md), [W4](W4_CPU_DRAWS.md),
[performance measurements](PERFORMANCE_LOG.md).

## Follow-up verification

- [Windows CI 38896616489](https://github.com/Retried/i3-pc/actions/runs/38896616489)
  for runtime f88d3b6f331272ce854bda5875c11386b180f94f completed successfully,
  confirmed once at this prompt. The original local W2 build/smoke pipeline
  also has exit 0. No duplicate CI/build job was started to obtain those results.
- The core/synchronization prerequisite capture found no Khronos validation
  layer. It recorded blocked with no emulator launch; validation was not run.
  Official Windows layers are provided by the
  [LunarG Vulkan SDK](https://www.lunarg.com/products/vulkan-sdk/).
  No SDK/global layer installation was performed.
- The optional package tools were included in a preview package using the
  existing binary. All 14 manifest files matched both folder and ZIP contents,
  with no private user tree/game_path/keys included. This verifies packaging,
  not the future Release/LTO executable or second-PC behavior.
- Windows PowerShell 5.1 capture exposed an unavailable Get-FileHash module;
  the tools now use .NET SHA-256. An initial 300-second capture exited 0 but
  exposed unordered action serialization and is not accepted as the intended
  opening-route check. Numeric action ordering was corrected and rechecked.
- The corrected 130-second opening run on Windows PowerShell 5.1 exited 0,
  confirmed NVIDIA and APP_VER 01.07 and had no matched critical/device-loss or
  validation messages. The four reviewed screenshots show loading, introduction
  text and the rendered coastal opening with geometry, foliage, water and light.
  This is an opening transition check; reference correctness remains unassessed.
- The new build launcher refused an attempted start while the emulator was
  active. Its worker/source-freeze/Release-LTO path awaits the actual final job;
  parser/guard/package checks do not establish a successful new build.

Local raw evidence is under `runtime/Build/w-delivery-20261016/`, including the
blocked prerequisite status, capture launch/status/logs/images, package manifest
verification and cleanup record. Compact reviewed results are in
[measurements/20261016-w-delivery.json](measurements/20261016-w-delivery.json).
No new FPS result is claimed by these smoke/tool checks.

## Cleanup

Removed 2697 generated compilation-intermediate files from the completed W2
build directory, totaling 1,536,664,926 logical bytes (about 1.43 GiB).
Targets were resolved under the workspace, checked for reparse points and
removed using native literal-path operations with no compiler/build running.
The old shadps4.exe, PDB and build-info hashes were verified unchanged. Old ZIPs,
user data, source dependencies, metadata-repair backup and raw W2-W4 evidence
remain. Reconfigure the old build directory before any incremental rebuild;
the retained executable remains usable.

## New second-PC build

The final action starts a new clean-source Windows x64 Release/LTO job with
three workers, then automatically packages and verifies it. Old artifacts are
not overwritten. Intended locations:

- Launch/source/configuration: `runtime/Build/pc2-20261016/launch.json` and inputs.json.
- Persistent stdout/stderr and final status.json: the same directory.
- Executable/metadata: `runtime/Build/pc2-x64-Clang-Release-lto-20261016/`.
- New package: `packages/i3-pc-PC2-20261016.zip`.

The launch record, not this document, provides the actual PID/start time and
source SHAs after publication. Build/package completion is pending until exit 0,
the expected executable and matching metadata/ZIP verification are recorded.
No second-PC launch is performed remotely; no second PC is available.
Use [PC2_ACCEPTANCE.md](PC2_ACCEPTANCE.md) with that machine when available.

## Checks that cannot be closed locally

Actual second-PC play, two-PC repeated comparisons, separate Vulkan layer runs, readback/long-gameplay
coverage and the atomic-fallback hardware reference checks remain unperformed.
The priority-2 optimization also needs a matching pre-change baseline; the
direct-draw environment switch does not isolate it. The priority-1 patch remains
unapplied. These are acceptance requirements, not implied successes.
