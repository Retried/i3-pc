# Design decisions

## 2026-10-15: Repository and documentation layout

The main repository holds scripts and project documentation. Emulator source is
the `runtime` submodule, with its URL pointing to `Retried/i3-pc` and its tracking
branch named `runtime`. Publish a runtime commit before publishing a main commit
that pins it. Documentation paths in the top-level `AGENTS.md` refer to the main
repository even when editing the submodule.

## 2026-10-15: Conservative incremental pipeline caching

Renderer priority 2 caches the register-derived render state and the previous
shader-variant lookup. Shader parameters, SRT memory, specializations and fetch
shaders still refresh for each draw or dispatch. The draw change mask alone
cannot account for guest-memory changes. Shader matching retains its resource
presence mask and existing fallback order; the on-disk cache format is unchanged.

The implementation is in runtime commit `9a719c45`. Windows build verification
does not establish a gameplay or performance improvement. Details and remaining
validation are in [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md).

## 2026-10-15: CI portability and bounded cleanup

Keep `__rdtsc()` on x86-64. Select `<intrin.h>` for MSVC/clang-cl and
`<x86intrin.h>` for other x86 compilers instead of changing the counter or adding
fences. Restrict formatting to the files covered by the fix; report inherited
findings rather than disabling CI or reformatting the repository.

REUSE copyright annotations for the 11 reported files use the recorded Git
author `i3-pc-port` and year 2026. Preserve their original GPL-2.0-or-later
declarations and list the exact paths in `runtime/REUSE.toml`.
Provenance and validation are in [CI_RUN_38766554875.md](CI_RUN_38766554875.md).

## 2026-10-15: Separate emulator and test builds

The current CMake configuration with `ENABLE_TESTS=ON` does not create the
emulator target. Validate the test configuration and the full emulator build
separately. Preserve existing tests and workflow checks, and report exclusions
and skips explicitly. Neither build nor test success replaces target-GPU or
gameplay validation.
