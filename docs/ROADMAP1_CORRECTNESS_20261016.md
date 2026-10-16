# Roadmap item 1: correctness ports

Target: Windows x86-64, AMD Ryzen, NVIDIA Vulkan, CUSA00004 v1.07.
Implementation base: runtime `f88d3b6f331272ce854bda5875c11386b180f94f`.
Changes are local and unpublished; runtime acceptance remains pending.

## Separate port boundaries

| Package | Upstream | Result |
| --- | --- | --- |
| rmdir | [#5373](https://github.com/shadps4-emu/shadPS4/pull/5373) | Nonrecursive removal and ENOTEMPTY. Missing paths return ENOENT before the type check; host status/removal errors use nonthrowing overloads and translate permission failures. Final symlinks are rejected as ENOTDIR; read-only mounts retain EROFS. |
| Timed mutex | [#5386](https://github.com/shadps4-emu/shadPS4/pull/5386) | An expired deadline attempts try_lock(), also covering zero/negative relative waits on Windows. |
| HTTP logs | [#5330](https://github.com/shadps4-emu/shadPS4/pull/5330) | Case-insensitive Authorization, Proxy-Authorization and Cookie filtering in insertion logs and template/connection/request dumps. Header storage and transport are unchanged. |
| Analog input, paired port | [#5340](https://github.com/shadps4-emu/shadPS4/pull/5340), [#5377](https://github.com/shadps4-emu/shadPS4/pull/5377) | Actual analog origin propagates through bindings, chords and remaps to stick/trigger updates, bypassing digital smoothing. Idle pad drift preserves keyboard smoothing; analog release stays immediate. Same-value source-mode changes update the controller. |
| Time/DST | [#5389](https://github.com/shadps4-emu/shadPS4/pull/5389) | Consistent signed offset and DST minutes, date-specific UTC/local and RTC conversions, date-specific local RFC formatting, and host-derived system-service timezone/summertime. |

Local mouse/right-stick handling, drift filtering, deadzones, halfmode, gestures,
hotkeys and scripted/virtual-controller paths remain in place. No renderer
optimization or portability path was removed. No repository tests were added,
following runtime/AGENTS.md.

## Adaptation decisions

The upstream time patch still uses today's timezone in several RTC/local-to-UTC
paths and assumes a one-hour Windows seasonal adjustment. This port instead
uses Windows dynamic timezone conversions and per-year standard bias, deriving
actual seasonal adjustment from the converted timestamps. RTC subseconds are
preserved; signed epoch arithmetic avoids pre-1970 unsigned underflow. Kernel
conversion failures are checked and optional output pointers are supported.

Windows reference: [time APIs](https://learn.microsoft.com/en-us/windows/win32/sysinfo/time-functions),
including SystemTimeToTzSpecificLocalTimeEx, TzSpecificLocalTimeToSystemTimeEx
and GetTimeZoneInformationForYear. Historical behavior depends on installed
Windows timezone data. Dates outside the Windows FILETIME conversion range
return an error. Guest policy for ambiguous/nonexistent local times and the
unused second kernel conversion argument still needs console evidence; the
host conversion policy is used without inventing a guest policy.

The input adaptation distinguishes a contributing analog binding from an idle
pad and from digital bindings. Simply OR-ing all analog origins would disable
keyboard smoothing whenever a resting controller was connected. Mouse axis
injection continues through its existing separate path.

## Validation

- Initial pending-build check found the PC2 launch/status paths from HANDOFF
  absent locally. The prior rejection remains authoritative; no success was
  inferred from missing records. No compiler/ninja/CMake/MSBuild was active
  before editing.
- Hardware: AMD Ryzen 7 5800X3D, NVIDIA GeForce RTX 2070 SUPER.
- Project clang-format and Git whitespace checks passed.
- Windows x64 clang-cl syntax checks passed (exit 0) for file_system.cpp,
  sync/mutex.cpp, time.cpp, http.cpp, rtc.cpp, systemservice.cpp,
  input_handler.cpp and input_mouse.cpp. Existing Release/LTO compiler flags
  were reused; the baseline executable was not overwritten.
- Syntax evidence: `runtime/Build/roadmap1-20261016/syntax-launch.json`,
  `syntax-status.json`, per-file response files and diagnostic logs.
- A manual host probe of the production time helper passed nine dates in the
  installed Central European Standard Time zone: January/July 2026, both sides
  of the March/October DST boundaries, January/July 2006 and December 1969.
  Unambiguous local/UTC roundtrips and out-of-range rejection passed. Evidence:
  `runtime/Build/roadmap1-20261016/time-probe-status.json`, `time-probe.log`
  and the copied-helper source. This does not execute guest RTC or prove
  console semantics, other timezones or the ambiguous-local-time policy.
- Full Release/LTO build record: `runtime/Build/roadmap1-20261016/build-launch.json`;
  final result is in `build-status.json`. The expected executable is
  `runtime/Build/roadmap1-x64-Clang-Release-lto/shadps4.exe`.
  The build is detached and is not awaited or repeatedly polled in this task.
- No gameplay, console hardware execution or benchmark was performed. Syntax
  success is not linking or runtime acceptance. No FPS effect is asserted.

## OpenOrbis hardware cases to share

Run these cases in an OpenOrbis console application and compare the same guest
calls in the Windows emulator. Record firmware, timezone/summertime settings,
arguments, return codes, errno, output structures and timestamps. Use a dedicated
writable scratch/save directory. These are reference cases, not passed results.

| Case | Procedure and comparison |
| --- | --- |
| Directory removal | mkdir/rmdir an empty directory; repeat with a child file and a child directory. Expect -1/ENOTEMPTY and intact children. Check missing path, ordinary file, final symlink where supported and read-only mount. Compare POSIX errno with sceKernelRmdir error translation. |
| Mutex | pthread_mutex_timedlock on an unlocked normal mutex with an expired CLOCK_REALTIME deadline should acquire it. With another thread holding it, expect ETIMEDOUT. Include deadline equal to now, positive future deadline, release before deadline and try-lock after timeout. |
| Input | Log scePadReadState axes/timestamps through neutral, partial/full deflection and release. Compare physical sticks/triggers, keyboard ramps, keyboard with idle/drifting pad, analog-plus-key chords, axis/button remaps, same-value source changes and virtual-pad input. Check mouse aim, gyro, swipes and two-finger gestures in CUSA00004 v1.07. |
| UTC/local | Compare sceKernelConvertUtcToLocaltime and both RTC directions for January/July, UTC, positive/negative and half-hour offsets, historical dates, DST transitions and optional null kernel outputs. Preserve RTC microseconds. Compare offset minutes with kernel offset seconds. |
| Historical rules | US Eastern: 2006-03-20 12:00 UTC should use -05:00; 2008-03-20 12:00 UTC should use -04:00. Warsaw: 2026-01-15 12:00 UTC uses +01:00 and 2026-07-15 uses +02:00. Check both sides of 2026-03-29 01:00 UTC and 2026-10-25 01:00 UTC. Record ambiguous/nonexistent local-time behavior without assuming invertibility. |
| Formatting/service | Format the same ticks using local RFC2822/RFC3339/precise variants; compare date and signed offset. Compare TimeZone and Summertime from sceSystemServiceParamGetInt with kernel timezone fields in winter/summer. |

HTTP host-log check: insert mixed-case sensitive headers at template, connection
and request levels; send to a controlled local endpoint. Confirm it receives
original values while insertion/dump logs omit them. Include an ordinary header
to confirm normal diagnostics remain.

Console references, target-game input/save/load acceptance and guest timezone
boundary checks remain pending.

Full Release/LTO build result, checked at the following prompt: complete,
exit 0, expected executable present and SHA-256 verified as
`8A79BF2D3FD773E4169A112E8F9F997CC4D212A6E72605814E4907D0259ACDF3`.
Records remain in `runtime/Build/roadmap1-20261016/build-status.json` and the
launch record. This does not close the pending console/gameplay checks above.
