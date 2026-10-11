# inFAMOUS Second Son PC build: benchmark and requirements

Measured 2026-10-09 on one PC. Everything under "Requirements" that was not measured on it is
marked as an estimate.

## Test PC

| Part | |
|---|---|
| CPU | AMD Ryzen 7 5700X3D (8 cores) |
| GPU | AMD Radeon RX 9060 XT, 16 GB |
| RAM | 32 GB |
| Display | 1920x1080, 144 Hz |
| OS | Windows 11 |

## Method

- Three fixed scenes loaded from saves, standing still, 30 s of frame times each:
  - **Billboard**: the opening spray-can scene (light).
  - **Cannery**: the interior after the tutorial (heavy).
  - **Outdoors**: free roam after the crash, where Delsin has gained his power (heavy).
- Frame cap 120, VSync off, hidden window, test build (RelWithDebInfo; the optimized build
  measured about 1 FPS higher in the cannery).
- The game always renders 1920x1080. "FSR 1" rows upscale that picture to the output size
  with the spatial FSR 1 pass; no temporal upscaler is involved.
- "Minimal" turns off the three effect switches (anti-aliasing, wet reflections, glow).
- 1% low = frame rate of the slowest 1% of frames.

## Results

| Scene | Output | Avg FPS | 1% low | 0.1% low | Worst frame | RAM |
|---|---|---|---|---|---|---|
| Billboard | 1080p native | 120.0 | 105.1 | 102.5 | 10 ms | 4.9 GB |
| Billboard | 1440p FSR 1 | 120.0 | 105.2 | 103.6 | 10 ms | 4.9 GB |
| Billboard | 2160p FSR 1 | 120.0 | 104.6 | 101.5 | 10 ms | 4.9 GB |
| Billboard | 1080p, effects Minimal | 120.0 | 106.1 | 102.7 | 10 ms | 5.0 GB |
| Cannery | 1080p native | 30.9 | 21.9 | 19.7 | 51 ms | 5.3 GB |
| Cannery | 1440p FSR 1 | 30.8 | 21.8 | 19.8 | 51 ms | 5.3 GB |
| Cannery | 2160p FSR 1 | 30.1 | 23.0 | 20.0 | 50 ms | 5.3 GB |
| Cannery | 1080p, effects Minimal | 31.8 | 22.8 | 20.1 | 50 ms | 5.2 GB |
| Outdoors | 1080p native | 37.3 | 21.2 | 19.9 | 50 ms | 5.3 GB |
| Outdoors | 1440p FSR 1 | 35.8 | 19.9 | 19.6 | 51 ms | 5.2 GB |
| Outdoors | 2160p FSR 1 | 35.8 | 25.5 | 19.8 | 51 ms | 5.2 GB |
| Outdoors | 1080p, effects Minimal | 37.1 | 22.0 | 20.1 | 50 ms | 5.2 GB |

## What the numbers say

- Light scenes hold the 120 cap at every output size.
- Heavy scenes run at 31 to 37 FPS, and neither output resolution nor the effect switches
  move that by more than about 1 FPS. The GPU is not the limit.
- The limit is one CPU thread: the thread that translates the game's draw calls is busy about
  95% of the time in these scenes (about 6,700 draws and 190 compute dispatches per frame).
- The 20 FPS floor in the lows (50 ms frames) is the game's own frame pacing stepping down
  when a frame is late, not a stall.
- The game presents on every Nth tick of the frame clock, so with the 120 cap a scene runs at
  40, 30, 24 or 20 FPS and nothing in between for long. A heavy frame costs about 30 to 32 ms
  of that one thread, just too slow for the 40 tier (25 ms). The tier is also not stable from
  run to run: the cannery read 30 in most runs and 21 in two others with identical settings.
  Heavy-scene averages here can therefore differ by a whole tier between runs.

## Speed-up attempts so far (same scene, same settings)

| Change | Result | Kept |
|---|---|---|
| Skip repeated no-op image layout transitions | 27.8 to about 31 FPS in the cannery (60 cap) | yes |
| Optimized (LTO) build | about +1 FPS | yes |
| Saved pipeline cache on disk | removes compile hitches | yes |
| Reuse identical small-buffer uploads within a batch | no measurable change | no |
| Promote repeatedly uploaded buffers to cached ones | slower (30 to 23 FPS outdoors) | no |
| Copy uploads on a worker thread (first multithreading step) | slower: 35 to 36 ms of thread time per frame against 30 ms | no |
| Turning off compute-result copies | breaks lighting | no |
| Record Vulkan commands on a worker thread (multithreading; ported from the SotC build) | 30.5 to 27.4-27.9 ms of thread time per heavy frame; cannery 31.0-32.1 to 34.4-34.7 FPS average | yes |
| Reuse a surface that flips between depth and float; cache texture descriptor decoding (from the SotC build) | no measurable change here | yes |
| Lift the game's own 30 FPS limit (new PC option "Game Frame Limit", on by default) | outdoors 30.0 locked to 32.3 FPS at a 60 cap; frame rate now follows frame cost instead of fixed steps | yes |
| Optimized (LTO) build of all of the above | cannery 37.1 FPS (25.4 ms of thread time per frame), outdoors 35.9 FPS, at a 60 cap | yes, in the shortcut's program |
| Remember exact-match texture lookups until the set of cached textures changes | 27.7 to 25.4-25.6 ms of thread time per heavy frame (test configuration) | yes |
| Optimized build with everything above (in the shortcut's program) | cannery 40.4 FPS average, 1% low 29.3, 22.5 ms of thread time per frame; crash site 45-46 FPS; 60/120 caps | yes |
| PS4 Pro mode | runs since a recompiler fix, same frame rate, but the picture is wrong (green tint, dither) | not offered |

## Shadow options (added 2026-10-09, evening)

About 70% of the game's draws go into shadow maps: roughly 4,200 of 6,000 per frame, of which
2,900 are the sun's map alone. Two new options on the in-game Graphics page, "Sun Shadows" and
"Light Shadows" (lamps and fires), set how often those maps are redrawn. Test build, outdoor
scene after the crash, standing still, 120 cap:

| Sun Shadows / Light Shadows | Thread time per frame | FPS | Picture |
|---|---|---|---|
| Every Frame / Every Frame (default) | 26.8 ms | 35 | original |
| Every 2nd Frame / Every 2nd Frame | 22.4 ms | 41 | same when standing and in a slow camera pan; fast movement not judged yet |
| Off / Every Frame | 22.5 ms | 41 | no sun shadows |
| Every Frame / Off | 24.7 ms | 37 | no change visible in this view |
| Off / Off | 18.8 ms | 47 | no shadows at all, flatter lighting |

These numbers are from the slower test build. The optimized build, which is the shortcut's
program since 2026-10-09 23:44 and contains the options, measured in the same scene (one run
each): both Every Frame 41 FPS, both Every 2nd Frame 44 FPS, both Off 52 to 53 FPS. The step
to Every 2nd Frame is smaller there than on the test build; why is not established.

A third option, "Shadow Detail" (Full / Reduced / Low), leaves draws under 300 or 1,000
indices out of the sun's shadow map (41% and 65% of its draws). In the test view the picture
is nearly identical. Optimized build, shortcut's program since 2026-10-10 00:22, same scene:
defaults 40 FPS; both shadow rows at Every 2nd Frame with Shadow Detail Low 47 FPS.

Since 2026-10-10 01:11 the shortcut's program also copies compute results back to the game
without blocking on the GPU (1.5 to 2 ms of every frame before). Same scene, optimized build,
one run each: defaults 42 to 43 FPS; both shadow rows at Every 2nd Frame with Shadow Detail
Low 51 to 52 FPS; both shadow rows Off 56 to 58 FPS. Cannery on the test build: 37.2 to 40.0 FPS.
A stable 60 in heavy scenes is still not reached at any setting.

Since 2026-10-10 02:25 the Graphics page has a "Shadow Preset" row that sets the three shadow
options at once. Same scene, optimized build (the shortcut's program), one run each:

| Shadow Preset | Sun / Light / Detail | FPS | Picture in the test view |
|---|---|---|---|
| Original (default) | Every Frame / Every Frame / Full | 43 | the game's own |
| Balanced | Every 2nd Frame / Every 2nd Frame / Reduced | 51 to 52 | same |
| Fast | Every 2nd Frame / Off / Low | 55 | same (no lamp or fire shadows in view) |
| Off | Off / Off / Full | 57 to 58 | no shadows, flatter and brighter |

Picture comparison: showcase/15_shadow_presets_original_balanced_fast_off.png (in that order,
left to right, top to bottom).

### Current numbers (2026-10-10 evening, after the crash fix)

The non-blocking copy of compute results (01:11 build above) turned out to be the cause of the
crashes in burning areas and while shooting: the game reuses that memory, and late copies
overwrote it. The copy blocks again since the 18:13 build, which is the shortcut's program.
That costs about 2 FPS, and the tables above from 01:11 on no longer describe the program.
Re-measured on the optimized build, standing still, 120 cap, four readings each:

| Scene | Shadow Preset | FPS |
|---|---|---|
| Crash site | Original | 40 to 41 |
| Crash site | Balanced | 45 to 48 |
| Crash site | Fast | 49 |
| Crash site | Off | 50 to 51 |
| Cannery | Original | 38 to 41 |

Road run from the cannery checkpoint (80 s, moving, Original): 46.3 FPS average, median frame
16.9 ms, 99% of frames under 34.5 ms, worst 51 ms, no frame over 100 ms inside the measured
window. No driver fault events during the session.

Why the worker thread did not help: the copies have to be finished before each batch of
commands is submitted, and the limiting thread submits often, so it ends up waiting for the
worker instead of doing other work, and the copy itself is slower on another core.

## Upscalers

- Available: FSR 1 (spatial upscale plus sharpening).
- Not available: FSR 3.1, FSR 4, XeSS. They are temporal upscalers and need per-pixel motion
  vectors, depth and sub-pixel camera jitter from the game. This build does not have those
  (the game renders without jitter and its velocity and depth buffers are not identified in
  the runtime), so none of them was benchmarked. Since heavy scenes are CPU-bound here, an
  upscaler would not raise their frame rate on this PC anyway.

## Requirements

Hard requirements (from how the program is built and what it uses):

- 64-bit Windows 10 or 11.
- CPU with AVX2 (the program is compiled for the x86-64-v3 level): Intel Haswell (2013) or
  newer, AMD Excavator or Ryzen.
- GPU with a Vulkan 1.3 driver.
- About 8 GB of memory is reserved at start and about 5.3 GB is used, so 16 GB of RAM in
  practice.
- The game data itself (30 GB).

Estimates, extrapolated from the one measured PC:

| | Minimum (estimate) | Recommended (estimate) |
|---|---|---|
| Target | 30 FPS in light scenes, 20 to 25 in heavy ones | 60+ in light scenes, 30 to 40 in heavy ones |
| CPU | 4 cores / 8 threads with AVX2, e.g. Core i5-8400 or Ryzen 5 2600 | 8 cores with strong single-thread speed, Ryzen 7 5700X3D class or faster |
| GPU | 4 GB, Vulkan 1.3, e.g. GTX 1650 or RX 570 | 8 GB, e.g. RTX 3060 or RX 6600 XT |
| RAM | 16 GB | 16 GB (32 GB if other programs stay open) |

Why these are only estimates: frame rate in heavy scenes follows single-thread CPU speed,
and only one CPU was measured; GPU load and video memory use were not measured at all
(the picture is a 1080p PS4 frame, so the GPU classes above are a cautious guess, not a
finding). A slower CPU than the test PC will be below 30 FPS in heavy scenes.

## Free roam from the edited saves (2026-10-10, 20:20)

Optimized build, Shadow Preset Original, 120 cap, scripted route of about 78 seconds (run, dash,
jump, turn, shoot). The saves are fixtures made with `tools/saveedit.py`; they skip the fight at
the longhouse.

| Scene | Average | Median | 99th percentile | Worst frame | Frames over 100 ms |
|---|---|---|---|---|---|
| Seattle, wrecked bridge ("Enter Seattle") | 59.7 FPS | 16.6 ms | 17.6 ms | 200 ms | 1 |
| Road checkpoint ("Walk to Seattle") | 50.9 FPS | 16.6 ms | 34.2 ms | 2667 ms | 10 |

The road run freezes once for about 3 seconds in every run (2.7, 3.4 and 2.9 seconds in three
runs, 37 to 48 seconds in); two repeat runs gave 51.2 and 52.1 FPS on average. The cause is not
found yet. The bridge run holds 60 with one 200 ms frame.
