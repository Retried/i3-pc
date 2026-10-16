# Review of upstream snapshot 6d2a7388

The requested wrapper commit `6d2a73881341858c09f488b2148d8048444f748b`
only advances the runtime pointer from `81b6211695fe3d1dc1b7712d7e6dcdef2c908275`
to `01201155b2daab7f0d3459c007317cf245660302`. The runtime changes are
`666858239f196d9124525a19fb9e377dacd61f90` and `01201155`.
This is a review of that specified snapshot, not every later upstream change.

## Integration decision

| Area | Decision | Reason |
| --- | --- | --- |
| SDL audio | Publish the existing formatting change separately as `2aa98f8b` | Include ordering, duplicate include removal and log formatting; no audio behavior change. |
| Sampler allocation | Accept | Clamp the driver limit to `MAX_SAMPLERS` before calculating collection thresholds. |
| Image pool collection | Accept with correction | Start collection when at least half the image slots are occupied, even below the memory trigger. Recheck occupancy before relaxing pressure after deletion. |
| Shader variant fast path | Retain our implementation | The proposed early return checks prior fetch-shader descriptors without reparsing fetch-shader instruction memory. A stable pointer does not prove unchanged instructions. |
| Recorder-thread upload copies | Do not adopt | Deferred reads of guest memory require a proven lifetime/synchronization model. The snapshot author reports intermittent incorrect Seattle lighting and makes this path opt-in. |
| Page-targeted queued-read drains | Do not adopt | These support the deferred upload path being excluded. Keep existing synchronous behavior. |
| Periodic pool/error diagnostics and upload counters | Do not adopt | Not needed for the selected correction; avoid new periodic error-level noise. |

The image collection correction keeps the existing age limits, deletion budgets,
download-safety checks, tiled-image handling and deferred destruction. The
upstream snapshot could relax pressure after its first deletion solely because
memory use was low, despite remaining slot pressure. The merged condition checks
both resources. Deferred slot destruction can keep occupancy high until the
scheduler releases the images; collection budgets still bound each pass.

The shader concern is visible in `vk_pipeline_cache.cpp` (`GetProgram`) and
`shader_recompiler/frontend/fetch_shader.cpp` (`ParseFetchShader`): descriptors
read through the previous parsed attributes cannot establish that the current
instruction stream has the same attributes, destination registers or element
counts. Keep our full specialization comparison and guest-code parsing until
an invalidation mechanism covers those dependencies.

This is a two-parent merge with the specified runtime snapshot. Its resulting
tree deliberately retains our versions of the excluded paths. Future merges
must not assume the excluded features were enabled merely because their commits
are ancestors.

## Validation and limits

Audio passes clang-format validation. The selected diff passes whitespace checks.
A focused Windows clang-cl `/Zs` check of the merged texture-cache translation
unit passed (exit 0), using existing compile-database flags and dependencies.
This validates syntax and types, not linking or runtime behavior.
Existing normal/LTO builds were still running when this task began; their sources
are left untouched by preparing the renderer merge in an isolated Git worktree.
Those builds do not validate the merged renderer. Clean Windows CI for the new
runtime revision remains required, along with gameplay/lighting and long-session
resource-pressure validation on the target NVIDIA GPU.

No benchmark was performed and no FPS improvement or fastest implementation is
claimed. The selection favors compatibility with a small, reviewable change.
