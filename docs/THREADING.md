# inFAMOUS Second Son PC build: can the translation thread be split up?

Written 2026-10-09 in answer to: "convert that translation thread into many native threads and
decompile properly", and the target of a stable 60 FPS in heavy scenes.

Short answer: one multithreading step is done and measured (about 10% of the thread's time).
Splitting the translation itself across many threads is possible in principle but has a low
ceiling with the current design, and 60 FPS in heavy scenes is not reachable by it. A native
port in the sense of running the game's own renderer on Vulkan directly is not something that
can be produced from the shipped game.

## Where things stand (cannery interior, 1080p, 120 cap)

| | Thread time per frame | Average FPS |
|---|---|---|
| Start of today | about 34 ms | 27.8 |
| After the image-transition cache | 30 to 31 ms | 30.9 |
| After moving Vulkan recording to a worker thread | 27.4 to 27.9 ms | 34.4 to 34.7 |
| Optimized build, game frame limit lifted | 25.4 ms | 37.1 |
| Texture-lookup memo, optimized build | 22.5 ms | 40.4 |
| Needed for the 40 FPS tier | under 25 ms | 40 |
| Needed for 60 FPS | under 16.7 ms | 60 |

The game presents on every Nth tick of the frame clock, so frame rate moves in steps
(40, 30, 24, 20 with a 120 cap). The next visible step needs about 10% more; 60 needs 40% more.

## What the game submits (measured)

- One submit per frame containing about 96 command buffers, 2.0 MB in total, about 21 KB
  each, the largest about 125 KB. The game builds them on its own job threads.
- About 16% of the buffers are byte-for-byte identical to one submitted in the previous
  three seconds.
- Those buffers decode to about 6,700 draws and 190 compute dispatches per frame.

## What the limiting thread spends its time on (profile, shares of that thread)

| Work | Share | Can it move to other threads? |
|---|---|---|
| Copying small buffers for upload (about 43 MB per frame) | 18% | Tried twice: slower. The copies must finish before each submit. |
| Vulkan driver calls | 12% | Done: recorded on a worker thread now. |
| Waiting for GPU results the game reads back | 11% | No. The game needs them in order. |
| Page-protection changes for tracking game writes | 6% | No. Tied to the order of commands. |
| Texture lookup | 7% | Not without redesigning the cache. |
| Pipeline and shader-variant lookup | 8% | Partly (see below). |
| Everything else: state decode, binding, render-pass handling | about 38% | Mostly order-dependent. |

## Options, with expected gain, scope and risk

| Option | Expected gain | Scope | Risk |
|---|---|---|---|
| Worker-thread Vulkan recording | 3 ms per frame, measured | done | low, verified in two scenes |
| Decode the 96 buffers in parallel, then replay in order | at most about 8% (2 ms). Only decoding and key building are independent of order; every cache lookup, memory-tracking update and render-target change is not | new front end plus a second pass; weeks | medium |
| Make the caches safe for look-ahead (versioned or sharded) so lookups can also run in parallel | perhaps 15 to 20% more | redesign of the texture, buffer and pipeline caches; the largest part of the renderer | high: these caches also track what the GPU has written into game memory, in order |
| Reuse the translation of identical buffers | under 5%: 16% of buffers repeat, but their contents point at game memory that changes, so resources must be resolved again; only decoding is saved | moderate | medium |
| Skip re-resolving state that did not change between draws | unknown, possibly 5 to 10%; the SotC build declined it because descriptors in game memory can change between draws | moderate | high: a wrong skip draws the wrong thing |

Adding the realistic items gives roughly 22 to 24 ms per frame: enough for the 40 FPS tier
in the cannery, with effort measured in weeks, not days. Reaching 16.7 ms would need all of
the above to succeed at the top of their ranges, including the high-risk cache redesign.
On these numbers, a stable 60 FPS in heavy scenes should not be promised.

## "Decompile properly": a real native port

- What exists is the game's compiled PS4 program. Its renderer is machine code that writes
  PS4 graphics commands (GNM); there is no source, no symbols for its render layer, and no
  higher-level draw list that could be read out and fed to Vulkan instead.
- A native port would mean reconstructing the engine's renderer from that machine code:
  finding its scene, material and draw-submission structures by reverse engineering and
  rewriting the submission to call Vulkan directly. That is a reverse-engineering project on
  the scale of the engine itself (16 MB of code), far beyond tuning.
- A middle route does exist in principle: hook the game's own functions that emit draws
  (above GNM) and emit Vulkan there. It would remove the command-stream decode, but not the
  resource resolution (textures, buffers and shaders still arrive as PS4 objects), which is
  where most of the time goes. Expected benefit is therefore small for a very large effort.
- The shaders are already translated to native GPU code once and cached; the game's CPU code
  already runs natively on the PC's processor. The cost that remains is translating graphics
  commands, which is what the table above is about.

## Recommendation

1. Keep the worker-thread recording (in the shortcut's program now).
2. Go for the 40 FPS tier next, cheapest first: texture-lookup cache per binding slot, then
   parallel buffer decode if the first is not enough.
3. Do not start the cache redesign or a renderer reconstruction without deciding that the
   weeks of work and the risk to a working game are worth a possible 60.
