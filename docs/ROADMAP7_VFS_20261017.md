# Roadmap item 7: VFS paths and mount matching

## Scope and integration

Adapted [upstream #5207](https://github.com/shadps4-emu/shadPS4/pull/5207),
merged commit `661d6fd0463a8ea5b441d3fcefd7d110a819c914`, onto runtime base
`f88d3b6f331272ce854bda5875c11386b180f94f` with items 1-6 retained.
The downloaded patch is in `runtime/Build/roadmap7-20261017/5207.patch`.

- MntPoints::SanitizeGuestPath validates empty/overlength/embedded-NUL input
  and lexically resolves repeated separators, dot and dot-dot components before
  mount selection. Absolute traversal stops at guest root; unmatched relative
  parents remain relative. The 255-byte input limit is retained.
- The helper is shared by VFS accessors, GetMount, mount/unmount registration,
  kernel open and reachability. Kernel open still reports ENAMETOOLONG for long
  input before normalization; invalid sanitized paths fail before handle allocation.
- Mount matching retains component boundaries and selects the longest matching
  mount, including nested mounts and a root mount. Thus /app0-other cannot match
  /app0, and /app0/../savedata0 selects savedata0's rights, not app0's rights.
- Identical host/read-only registrations are idempotent. Changed registrations
  replace the existing pair only after constructing its backend stack; no
  duplicate mount is appended. Mount/unmount invalidates the host case-search
  cache. Normalized spellings also identify the same mount on unmount.
- Mod/patch eligibility uses the selected mount's exact /app0 or /hostapp name.
  Mods, update/patch and base backend precedence, .zar support, ignore-patches,
  explicit HostPathType behavior and host path configuration remain intact.
- NormalDirectory owns its guest path string, avoiding a dangling view after
  a normalized temporary or original caller's storage expires. Directory type
  selection now uses an app0 component boundary, with the obsolete dot-dot TODO
  removed. Existing PFS layouts and the item-1 rmdir correction are retained.

## Windows and guest-root adaptations

Guest normalization processes slash-separated components directly rather than
using the host-native filesystem parser. This prevents a leading // from being
interpreted as a Windows UNC root. Windows rejects backslash/colon syntax here
instead of passing drive, stream or alternate separator syntax to host joins.
Those restrictions are Windows-only; existing host path and portable renderer
paths are unchanged. Trailing directory separators are retained where meaningful.
This is lexical normalization, not a symlink resolver or a guest-CWD implementation.

The guest root exists, is a directory, can be opened/enumerated as a directory
and is reachable. A shared root-entry snapshot lists unique top-level mount
names, with dot entries supplied by IterateDirectory. Callbacks run after the
mount-list lock is released. Open rejects the root as a regular file.
Unlike upstream's GetHostPath return of '/', the virtual root has no host path
and is reported read-only, so host filesystem operations cannot target a drive
root. Stat recognizes normalized root spellings and uses the existing synthetic
root metadata. Nested mount entries are listed by their first component.

The existing mount-pointer lifetime/concurrency contract is not redesigned by
this port. Existing open file handles keep their backend ownership on remount.
Identical re-registration is not an overlay hot-reload mechanism.

## Validation and records

- Follow-up on the item-8 prompt: the full build completed with exit 0;
  executable present and SHA-256 verified as
  `EA55565AEE549B0C5CAF111C0657B03688F10EC0017608C928C4CE571D5054D4`.
  Runtime acceptance remains pending.

- Item-6 Windows x64 Release/LTO build completed with exit 0. Its executable is
  present and SHA-256 verified:
  `E95763D8B48C956F9E970EB2709BE55131C8B2A776714F56CB9E0EE2489235FC`.
  It is preserved as the pre-item-7 baseline.
- Windows x64 clang-cl syntax checks passed with exit 0 and empty diagnostics
  for fs.cpp, normal_directory.cpp, pfs_directory.cpp, file_system.cpp and
  savedata.cpp. Changed-range clang-format and whitespace checks passed.
  Source review covers normalization before permission lookup, component
  boundaries, remount identity, root access and unchanged overlay precedence.
  These checks do not establish gameplay or guest syscall acceptance.
- Records: `runtime/Build/roadmap7-20261017/syntax-launch.json`,
  syntax-status.json, per-source response files/logs, format-status.json and
  item7.diff. No repository tests were added, following runtime/AGENTS.md.
- Full Windows x64 Release/LTO launch record:
  `runtime/Build/roadmap7-20261017/build-launch.json`; final result belongs in
  build-status.json. Expected executable:
  `runtime/Build/roadmap7-x64-Clang-Release-lto/shadps4.exe`.
  The worker records source SHA/dirty state/file hashes and persistent logs.
  Separate native log consoles are recorded in syntax-console-launch.json and
  console-launch.json; no desktop input or activation automation is used.
- No console reference, game save/load, Vulkan validation or benchmark run is
  claimed. No FPS effect is asserted.

## Pending OpenOrbis reference cases to share

Share a sample using open/stat/getdents/reachability and save-data mounting.
Record return values, errno, normalized target selection, directory names,
file contents and hashes on console and Windows AMD/NVIDIA. Use disposable
sample files, leaving real game saves untouched.

| Case | Procedure and expected comparison |
| --- | --- |
| Canonical spellings | Read the same file through /app0/file, /app0//file, ///app0/./file and /app0/sub/../file. Compare contents and lookup target. |
| Crossing mounts | Access /app0/../savedata0/file and /savedata0/../app0/file. Compare read/write permissions with canonical paths, including nonexistent create targets. |
| Boundaries | Compare /app0, /app0/, /app0-other and /app01. With a nested mount, verify the more specific mount wins regardless of registration order. |
| Root | Compare /, ////, /app0/.. and /../../. Check synthetic stat, read-only directory open, enumeration with dot entries, reachability and failed regular-file/write operations. |
| Input validation | Cover empty and relative paths, 255/256-byte inputs and Windows drive/stream/backslash spellings. Record supported guest behavior separately from host-representation rejection. |
| Mount lifetime | Register identical pairs repeatedly, replace host/read-only state, and unmount using normalized aliases. Check one root entry, changed permissions and subsequent access to the replacement backend. |
| Overlays | Use distinct base/patch/mod contents and overlay-only files; compare canonical and dot/dot-dot spellings, merged enumeration, .zar backends, ignore-patches and explicit base/patch/mod selection. |
| Directory ownership | Open a directory from temporary path storage, release/overwrite that storage, then read/getdents/rewind repeatedly. Compare stable names and PFS/normal directory ABI. |
| Save/load | In a disposable save slot mount, create/write/flush/close/read/rename/unlink/rmdir and remount. Compare hashes and ensure read-only app mounts stay read-only. |
| Target game | CUSA00004 v1.07 new/load/save, transitions, restart and save reload with the same overlays. Compare existing files and hashes; console and gameplay acceptance remain pending. |
