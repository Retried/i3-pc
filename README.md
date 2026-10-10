# inFAMOUS Second Son: unofficial PC build scripts and notes

This repository holds the wrapper around a game-specific build of the
[shadPS4](https://github.com/shadps4-emu/shadPS4) emulator that runs inFAMOUS Second Son
(CUSA00004, v1.07) on Windows: build and install scripts, the launcher and settings scripts,
test scripts and the benchmark and investigation notes.

It is an unofficial, game-specific build derived from shadPS4. It is not affiliated with or
endorsed by Sony Interactive Entertainment, Sucker Punch Productions or the shadPS4 project.

## What is not here

No game files, no PS4 system modules, no keys, no saves, no shader caches, no screenshots or
videos, and no icons, fonts or textures from the game. You need your own legally obtained copy
of the game. The program icon is not included either: `dist/Install.ps1` uses `dist/game.ico`
if you put one there. `dist/Keys.ps1` redraws the button icons as key caps on top of the game's
own icon sheet, which you have to dump from your copy first (`dist/glyphs/atlas_original.raw`);
without it the key bindings still work and the icons stay as they are.

## Layout

| Path | What |
|---|---|
| `runtime/` | The emulator source (git submodule, branch `runtime` of this repository): shadPS4 plus the changes for this game |
| `build.bat`, `build-lto.bat` | Build the runtime with clang (test build / optimized build) |
| `install.sh` | Copy the test build to `bin/i3.exe` |
| `dist/` | What sits beside the finished program: `Play.bat`, `Settings`, `Keys`, `Install`, `README.txt`, default key bindings |
| `*.sh` | Headless test, benchmark, frame-time and scripted-play runs |
| `tools/` | Profiler summary, SPIR-V helpers, one-off source patch scripts |
| `docs/` | Benchmark, threading study and play/stability notes |

## State

Playable from the keyboard from the tutorial to the first boss fight; see `docs/NOTES.txt` and
`docs/BENCHMARK.md` for what is verified, what is measured and what is still open.

## Licence

The runtime is a derivative of shadPS4 and is licensed under GPL-2.0-or-later, as are the
scripts in this repository. See `LICENSE`.
