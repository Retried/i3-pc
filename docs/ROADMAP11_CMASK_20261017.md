# Roadmap item 11: separate CMask port

Port source: [shadPS4 #5046](https://github.com/shadps4-emu/shadPS4/pull/5046),
commit [995e37e4e77ea9f3ec69367f9ec00867201ca191](https://github.com/shadps4-emu/shadPS4/commit/995e37e4e77ea9f3ec69367f9ec00867201ca191).
The local port was compared against current sources, with earlier renderer ports
retained. It is separate from the readback dependency guards and does not import
the larger #3396 GC/readback work.

The source boundary is recorded before the readback changes in
`runtime/Build/roadmap11-20261017/cmask-only.diff`. The final combined delta and
before-source snapshots are retained beside it. No standalone patch application
is needed to build the integrated runtime.

## Behavior

Buffer metadata reads synthesize expanded CMask patterns for the live owner's
guest sample count: 1/8 samples use 0xFFFFFFFF, 2 use 0xDDDDDDDD and 4 use
0xEEEEEEEE. HTile keeps its existing uncompressed fill; FMask remains on its
existing unhandled fallback. Normal buffer/resource synchronization remains.

Metadata records now identify their owner by ImageId and monotonically assigned
image UID. Registration replaces a changed owner/type while preserving an
existing owner's consumed clear state on rebind. Moving/disabling a metadata
address unregisters the old association. Deletion removes only that image's
record, so deleting an older owner cannot erase a newer owner's association at
the same address. Lookup rejects freed/recycled/unregistered image owners.

## Local hardening and clear-state audit

- Unsupported sample counts return an empty optional, preserving fallback.
  Upstream's default optional value of zero would be engaged; it is not used
  as a silently supported encoding here. Unaligned fill ranges also fall back.
- IsMeta, IsMetaCleared, ClearMeta and TouchMeta all require a live owner.
  Slice queries/updates beyond the existing 32-bit clear mask return false
  instead of shifting out of range. No wider-layer mask is invented.
- The same owner retains its current clear mask when rebound. A different
  owner/type receives initial metadata state, including the depth target's
  HTile mask. Existing fast-clear elimination and per-slice touch behavior remain.
- Synthesizing expanded metadata does not itself consume or restore the virtual
  clear mask. Host image clearing/decoding and metadata-read synthesis remain
  distinct operations. The depth/stencil association and depth/float reuse ports
  are retained.

## Pending reference acceptance

Share an OpenOrbis workload that creates color targets with 1/2/4/8 samples,
reads their CMask through buffer access and records raw words plus rendered
checksums before/after fast-clear elimination. Rebind unchanged targets and
touch individual slices to verify that consumed clear state is not restored.

Reuse one metadata address across owners and types, disable/change its address,
park/re-register depth/float aliases, and delete the old owner after registering
the new one. Include recycled slot IDs with different UIDs, unregistered owners,
unsupported sample counts and slice 31/32 boundaries. Compare with console
reference and separate Vulkan validation on Windows AMD/NVIDIA.

These cases and CUSA00004 v1.07 rendering/readback acceptance are pending. Build
and syntax evidence for both parts of item 11 is linked from
[ROADMAP11_READBACK_20261017.md](ROADMAP11_READBACK_20261017.md); no GPU correctness
or FPS result follows from source integration.
