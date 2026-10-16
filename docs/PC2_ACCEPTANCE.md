# Second-PC acceptance

Target: Windows x64, AMD Ryzen CPU, NVIDIA Vulkan GPU, own CUSA00004 APP_VER 01.07
dump. This package contains no game, firmware, keys, saves or private settings.
Keep the older package until this release has passed acceptance.

## Play without development tools

Extract the ZIP into a writable directory. Install the NVIDIA driver and the
Microsoft Visual C++ 2015-2022 x64 Redistributable if missing. Put the absolute
path to your own eboot.bin in game_path.txt, then start Play.bat. Python, Git,
Visual Studio, CMake and LLVM are not required to play.

Record the package SHA-256, build-info.json and machine/driver identity. Check
actual audio, keyboard/controller input, opening, save/load and scene changes.
Inspect rendering and particle effects against a known correct image, then run
a longer gameplay session. A successful startup alone is insufficient.

## Isolated automatic capture

The optional tools require 64-bit Windows PowerShell 5.1 or newer and vulkaninfo.
The latter may be supplied by the driver or a local Vulkan SDK. No global SDK
installation or registry changes are performed by these tools. Missing tools,
AMD CPU or an unambiguously enumerated NVIDIA device stop the run.

From the extracted package, using new output directories:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/accept-windows.ps1 -Executable './inFAMOUS Second Son.exe' -Game 'E:/Games/CUSA00004/eboot.bin' -OutputDirectory './checks/opening' -Mode smoke -DurationSeconds 300
```

The script verifies executable metadata and the game's SFO, explicitly selects
NVIDIA, creates isolated user data, records startup/exit/logs/screenshots and
samples process memory/CPU. -UserSeed can copy your existing local user directory
without modifying it. The fixed script presses cross during the opening and
does not constitute a performance benchmark.
DurationSeconds is relative to the first presented frame; a bounded startup
allowance is added. Timeout termination targets only the process it launched.

Core/synchronization and GPU-assisted validation are separate captures:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/accept-windows.ps1 -Executable './inFAMOUS Second Son.exe' -Game 'E:/Games/CUSA00004/eboot.bin' -OutputDirectory './checks/core-sync' -Mode core-sync -LayerDirectory 'C:/VulkanSDK/<version>/Bin'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/accept-windows.ps1 -Executable './inFAMOUS Second Son.exe' -Game 'E:/Games/CUSA00004/eboot.bin' -OutputDirectory './checks/gpu' -Mode gpu -LayerDirectory 'C:/VulkanSDK/<version>/Bin'
```

Supply the real SDK path. A missing layer yields status blocked and no emulator
launch, not a passing validation result. A validation capture requires both the
explicit enabled-layer log and absence of matched validation messages. Inspect
all logs and images; status captured is not automatic gameplay acceptance.
The official layer is distributed in the
[LunarG Vulkan SDK](https://www.lunarg.com/products/vulkan-sdk/).

## Matching performance captures

Use the wrapper's tools/benchmark.py and docs/W3_BENCHMARKS.md with Python 3.11+
on both PCs; development/compiler tools are not required for capture. Point
--executable at this package's executable and --user-seed at a private seed with
the same save/scene as PC1. Use identical matrices/settings, 3-5 independent
repeats, separate cold/warm emulator cache and alternating A/B. Keep driver cache
state explicit. Review visuals and stability before interpreting timing.
Use repeatable inputs available for this delivery and keep control-scene results
limited to their measured scope.

## Return evidence

Keep raw run directories locally. Review files before sharing: user copies may
contain private saves/keys and logs may contain local paths. Share reviewed
status.json, hardware/diagnostics.json, build/package identity, relevant logs,
images and benchmark summary/raw frame intervals. Do not share user/keys.json,
firmware or game data. No tool uploads anything automatically.

The tracked reports distinguish delivered implementation from external acceptance.
Second-PC gameplay and validation must be recorded as
actual results before the complete W1-W4 acceptance can be called finished.
