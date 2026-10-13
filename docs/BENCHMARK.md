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

The road run froze once for about 3 seconds in each of three runs (2.7, 3.4 and 2.9 seconds, 37
to 48 seconds in; 51 to 52 FPS on average). A fourth run held 60.0 FPS with a worst frame of
18 ms only because its route never reached the spot; the freeze returned in later runs (2.3 to
3.1 seconds), so it was not first-time shader work. The bridge run holds 60 with one 200 ms
frame, and three minutes of continuous play there (2026-10-11) gave 60.0 FPS, 99th percentile
17.7 ms, worst frame 33 ms.

Cause of the road freeze, measured with the freeze log (`I3_FREEZELOG=1`): at that point the
game first binds its two geometry heaps whole and read-only (2.5 GB and 0.5 GB, 16-bit data
indexed by a per-instance offset), and the runtime uploaded all of it in one frame: about 3 GB
copied, 1.6 of the 2.3 seconds; image uploads were another 0.3. Bounding the buffers would be
unsound because of the offset. From runtime 673a9c8 the heap ranges are remembered and uploaded
16 MB a frame from the start of the session, so the first bind finds only recent writes, and
large uploads copy on six threads. Test build, same run: worst frame 2401 ms without the
ranges, 451 ms with them (what remains is image uploads); 60.0 FPS before the bind either way.

## Copy back of compute results (2026-10-13)

Optimized builds of 2026-10-11 died in the shooting soak (`shootsoak.sh`, three minutes of
firing in the first boss arena) in three runs of four. The crash records show the game's own
memory overwritten: a copy command of the game with a garbage address, and null reads in game
code. Two changes followed in the runtime: the argument slots of an indirect draw are copied
back to game memory when the GPU wrote them, and a compute output is copied back only where the
GPU changed it, so that what the game wrote into the same range meanwhile is kept
(`I3_NO_ARG_MIRROR=1` and `I3_MIRROR_WHOLE=1` switch them off).

The crash did not come back in the test that was meant to confirm this (`crashtest.sh`, seven
soaks: three with both changes, one with the second switched off, one with both off, two of the
build from before): all seven stayed alive, the old build included. The display had been set
to 60 Hz between the crashes and this test, which may matter. So the cause is not confirmed;
the changes are kept because they are right on their own and cost nothing measurable.

Crash site, optimized builds, alternating runs (`abtest2.sh`):

| Build | Length | Average | 99th percentile | Worst frame | Copy back per 3 s |
|---|---|---|---|---|---|
| Before the changes, run 1 | 63 s | 47.2 FPS | 34.4 ms | 3366 ms | 185 ms |
| With the changes, run 1 | 70 s | 47.9 FPS | 34.4 ms | 250 ms | 231 ms |
| Before the changes, run 2 | 96 s | 48.4 FPS | 34.2 ms | 51 ms | 244 ms |
| With the changes, run 2 | 96 s | 47.1 FPS | 34.5 ms | 51 ms | 260 ms |

Run 1 of each started late and is shorter. The build from before froze once in each run in the
first seconds after the save loaded (3.4 seconds, and 2.3 seconds in run 2, there before the
measured part began); the changed build did not (0.25 seconds at most). The soak shows the same:
3.4 and 2.2 seconds before, 0.75 seconds at most after. A first version of the second change compared every four bytes with a
library call and searched a list of about 880 outputs each frame: 45.5 FPS against 48.1. The
version above finds them by key.

## Benchmark clips (2026-10-13)

`bench_*.mp4` in the showcase, 24 seconds each, made by `benchvideos.sh` on runtime 76a2edaf
(`bench_<name>_1080.mp4` at 1080p, `bench_<name>.mp4` at 720p). The panel is drawn into the
runtime's own capture afterwards: frame rate, average and 1 % low from the start of the clip,
frame time, total CPU load and the busiest thread, video memory, RAM and a frame time graph.
GPU load is not shown: Windows reports about 1 % for this program whatever it draws.

The last line of the panel is the frame rate without recording, measured in the same run over
the 12 seconds before recording starts, with the character standing at the clip's first view.
In the clip the camera turns or the character runs, so the recorded average covers other views
and can lie above that figure (crash site on Original, cannery).

| Clip | Scene | Shadow Preset | Recorded average | 1 % low | Worst frame | Standing, not recorded |
|---|---|---|---|---|---|---|
| bench_crash_original | Crash site | Original | 37.8 FPS | 20.0 | 51 ms | 35 FPS |
| bench_crash_balanced | Crash site | Balanced | 45.2 FPS | 29.1 | 35 ms | 45 FPS |
| bench_crash_fast | Crash site | Fast | 45.9 FPS | 29.2 | 50 ms | 46 FPS |
| bench_crash_off | Crash site | Off | 48.9 FPS | 29.1 | 35 ms | 50 FPS |
| bench_cannery | Fish cannery interior | Original | 48.0 FPS | 29.2 | 35 ms | 40 FPS |
| bench_road | Road to the cannery, running | Original | 52.5 FPS | 29.2 | 50 ms | 56 FPS |
| bench_city | Seattle bridge, running | Original | 59.9 FPS | 56.7 | 33 ms | 60 FPS |

No clip has a frame over 51 ms. A first recording of the same seven an hour earlier gave 37.4,
44.4, 46.9, 47.8, 47.2, 51.5 and 59.8 FPS, with one frame of 150 to 283 ms in three of them.
The clips of 2026-10-11 (build before the copy-back changes, 21 seconds, another display rate)
gave 39.2, 45.1, 46.8, 50.0, 47.8, 53.6 and 60.0 FPS.

## Seattle, looking at the city (2026-10-13)

Steered by hand from the Seattle save (`livestart.sh`, `livestep.sh`). Looking along the wrecked
bridge the game holds 60 FPS, which is what the bridge clip and the earlier bridge runs show.
Turning the camera to the city (the checkpoint across the water, the Space Needle behind it)
the optimized build falls to 21 to 22 FPS and stays there: about 45 frames over 40 ms in every
3 seconds, none over 67 ms. The render thread is then busy 2.9 of every 3.0 seconds; two game
threads sit at 95 and 72 %; the graphics card is not the limit.

Profile of that view (`cityprof.sh`, test build, 25.7 FPS, 38 ms of render-thread time per
frame): no single hot spot. The time is spread over the work done for every draw: copying small
buffers into the stream buffer (about 10 %), looking up the shader variant for each stage
(about 12 %), binding buffers and textures, the barrier bookkeeping for buffers (about 8 %) and
page protection for uploads (about 8 %). The parts the runtime times itself (copy back,
dispatches, flushes) are 0.4 of the 2.9 seconds. Reaching 60 there needs the per-draw cost cut
to less than half or spread over more than one thread; neither is done.

### What that view costs, and the first cut (2026-10-13)

`cityview.sh` reaches the view the same way every time (13 turn steps from the save) and
measures 24 seconds. Optimized build:

| Shadow Preset | Frame rate |
|---|---|
| Original | 23.2 FPS |
| Balanced | 23.0 FPS |
| Fast | 25.2 FPS |
| Off | 23.9 FPS |

So shadows are not the cost. Counted with `I3_PASSSTAT=1`: about 9,100 draws a frame, 6,400 of
them in the main pass, and 5,450 with a single shader pair (vertex 0xbeb7156, fragment
0x6353e48b): 190 indices on average, two in five with at most 36. `cityskip.sh 6353e48b` shows
what it is: with those draws left out the distant skyline is gone (the Space Needle, the far
buildings) and the same view runs at 36.6 FPS instead of 23.5. Between two such draws the game
changes only per-object constants, the index buffer and the instance count in 94 % of cases.

Time per stage of a direct draw on the test build (ms of render-thread time per 3 seconds, of
2,900): binding buffers and textures 1,014, pipeline lookup 443, releasing bindings 329, vertex
buffers 248, starting the render pass 118, descriptors 118. And 4.3 million copies of small
read-only buffers into the stream buffer per 3 seconds (930 MB a second), of which 65 % repeat
an address and size copied a moment before.

Runtime c774955b stops tracking reads of the stream buffer (the GPU never writes it; releasing
bindings fell from 329 to 33 ms) and binds a repeated copy again instead of copying it again
while nothing can have changed the memory. Optimized builds, alternating (`cityab.sh`): 22.9 and
22.8 FPS before, 25.9 after; crash site 47.8 before, 50.4 after; shooting soak alive with no
dropped draws. The first run of a new build after an old one does not reach the view in time
(its pipeline cache is rebuilt) and is not counted.

Still far from 60 there. What remains is spread over the work each of the 9,100 draws needs;
the next candidates are a short path for a draw that follows one with the same pipeline and
only new constants, and reusing the texture bindings of the draw before.

## The crash in long fire fights (2026-10-13)

`shootsoak.sh` (three minutes of firing in the first boss arena) killed optimized builds in
about one run of three, always 112 to 136 seconds in, after dropped indirect draws had grown
from a few to 60 or 80 every 3 seconds. Two different game instructions faulted, both on
garbage data.

Found with the emulator's precise readback (made to run on Windows for this) and a log of every
game read of GPU-written memory: the game reads the small outputs of five compute shaders about
nine times a frame, right after its completion signal, from memory it hands out anew every
frame. The copy back at the end of the frame came too late, so it read leftovers.

| Variant (optimized builds unless noted) | Soaks alive | Dropped draws | Soak | Crash site |
|---|---|---|---|---|
| Copy back at the end of the frame (before) | about 2 of 3 | up to 472 | 57 FPS | about 50 FPS |
| Copy back of everything at every completion signal | 2 of 2 | 0 | 23 FPS | |
| The same at label writes only / at release only | 1 of 1 each | 0 / 1 | 24 / 17 FPS | |
| Label writes held back until the next flush | game stops in 2 s | | | |
| Copy-back limit 1 MB instead of 16 KB | 2 of 3 | 170 in the dead run | 53 FPS | |
| Last frame's result written at dispatch (prediction) | 1 of 4 | 86 to 165 | 53 FPS | 47 FPS |
| On-demand readback, relaxed / precise (test build) | 1 of 1 each | 55 / 0 | 54 / 32 FPS | |
| Those five shaders' outputs, with all pending, at the next signal | 3 of 3 | 0 | 32 to 34 FPS | 33 FPS |
| Those five shaders' outputs only, at the next signal | 4 of 4 | 1, 0, 0, 0 | 44 to 46 FPS | 41.7 FPS |
| The same, GPU wait polled before blocking (installed) | 3 of 3 | 1, 0, 0 | 49 to 53.5 FPS | 41.6 FPS |

The installed variant waits for the graphics card about 2.4 times a frame at the crash site;
the wait is for the card to catch up with the frame so far, which is why it costs more than the
copy itself. With the frame clock at 144 the crash site runs at 36.6 FPS (median 27.6 ms)
instead of 52.2 FPS (median 20.5 ms) before the fix. Not blocking the command thread at all,
and writing the game's label only when the results have landed, is the next thing to try.

## Frame clock (2026-10-13)

`clocktest.sh`, crash site, build before the crash fix: 60 Hz 49.3 FPS with 226 frames over
34 ms; 120 Hz 50.9 FPS with 10; uncapped 50.8 FPS with 5 (median 20.0 ms); 144 Hz 52.2 FPS,
99th percentile 28.7 ms. The game presents once per tick, so a 60 Hz clock turns a frame of
18 ms into one of 33 ms.
