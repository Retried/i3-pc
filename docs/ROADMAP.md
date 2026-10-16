# Priorities

Work only on the requested scope. Delivered W1-W4 implementation work has been
removed from the implementation checklist; its evidence is consolidated in
[W_DELIVERY_20261016.md](W_DELIVERY_20261016.md). W1-W4 are distinct from renderer
priorities 1-7. Complete acceptance is not claimed.

## Remaining release acceptance

- Check the new second-PC build/package result once, then launch it on a second
  AMD/NVIDIA PC and record gameplay acceptance using [PC2_ACCEPTANCE.md](PC2_ACCEPTANCE.md).
- Supply a Khronos layer for separate core/synchronization and GPU-assisted runs;
  record the release's rendering, save/load/readback and stability checks.
  Only one PC is currently available.
- Complete matching two-PC benchmarks and isolate priority-2 commit `9a719c45`
  with a matching pre-change baseline. Existing title-control A/B does not do this.
  Investigate the documented atomic fallback with hardware reference cases.

These unperformed checks are retained as release acceptance, not marked done
by moving the delivered implementation milestones out of the checklist.
Historical upstream investigation items are outside this delivery's scope.

Renderer priority 2 is implemented; gameplay and measurements remain unverified.
Priority 1 remains an unapplied experimental patch.
Read the relevant section of [PERFORMANCE_ROADMAP.md](PERFORMANCE_ROADMAP.md)
only when planning renderer work. Pending execution state is in [HANDOFF.md](HANDOFF.md).
