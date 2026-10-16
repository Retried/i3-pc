# i3-pc

Windows build tools, launcher and runtime integration for a focused compatibility
project. This repository contains build and packaging scripts, desktop controls,
configuration tools and development documentation. The runtime sources are in the
[`runtime`](runtime/) submodule, maintained on this repository's `runtime` branch.

The project is a work in progress. Release acceptance and testing on a second PC
are still pending; see the [acceptance checklist](docs/PC2_ACCEPTANCE.md).

## Build and package

The current build and validation target is Windows 10/11 x86-64 with an AMD Ryzen
CPU and an NVIDIA GPU supporting Vulkan 1.3.

Install Git, Python 3 and Visual Studio 2022 or Build Tools with Desktop development
with C++, a Windows SDK, C++ Clang tools and C++ CMake tools. CMake 3.30 or newer,
Ninja and a complete x64 LLVM installation are required. See the
[Windows build instructions](docs/W1_WINDOWS.md) for dependencies and tool overrides.

```powershell
git clone --recursive https://github.com/Retried/i3-pc.git
cd i3-pc
.\build.bat
powershell -NoProfile -ExecutionPolicy Bypass -File tools/package-windows.ps1
```

For a Release build with link-time optimization, use `build-lto.bat` and pass
`-BuildDirectory runtime/Build/w1-x64-Clang-Release-lto` to the packaging script.
Packages are written to `packages/`. Extract a package to a writable folder and
follow its `START-HERE.txt` instructions.

Use the recursive clone above on a second PC to obtain both the wrapper and the
pinned runtime sources. Compiled executables, local build directories and ZIP
packages are ignored by Git; build and package locally using the commands above.
To update an existing checkout, run `git pull --ff-only`, followed by
`git submodule update --init --recursive`.

Content, saves, keys and proprietary system components are not distributed with
this project. You must supply your own legally obtained compatible content; see
the [detailed setup and usage guide](docs/LEGACY_README.md#how-to-play-step-by-step).

## Documentation

Project documentation is maintained in English. Chat and collaboration may
continue in Polish or the user's preferred language.

- [Build and packaging](docs/W1_WINDOWS.md)
- [Setup, controls and historical captures](docs/LEGACY_README.md)
- [Release acceptance](docs/PC2_ACCEPTANCE.md)
- [Roadmap](docs/ROADMAP.md)
- [Benchmark method](docs/BENCHMARK_PROTOCOL.md) and [measurement log](docs/PERFORMANCE_LOG.md)

## Repository layout

| Path | Contents |
|---|---|
| `runtime/` | Runtime source submodule |
| `build.bat`, `build-lto.bat` | Windows build entry points |
| `dist/` | Launcher, settings, controls and package documentation |
| `tools/` | Build, packaging, diagnostics and development utilities |
| `docs/` | Guides, technical notes and historical measurements |

## Reporting problems

Open an issue in this repository with reproduction steps, your CPU and GPU, and
relevant log output from `dist\user\log\shad_log.txt`. Do not attach proprietary
content, keys or saves.

## Upstream and licence

The runtime is derived from [shadPS4](https://github.com/shadps4-emu/shadPS4), with
project-specific changes. The runtime and the scripts in this repository are
licensed under GPL-2.0-or-later; see [LICENSE](LICENSE). Original copyright and
licence notices remain in the sources. This is an independent project and is not
affiliated with or endorsed by the upstream project or the content owners.
