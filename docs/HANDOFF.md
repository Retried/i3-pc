# Pending continuation

- Check [CI 38862336590](https://github.com/Retried/i3-pc/actions/runs/38862336590)
  for runtime `b499ca72329ab179c365ca695570d6d79e57a998`: Windows build/tests,
  clang-format and REUSE. Local clang-format 19.1.7 validation passed all 931
  source files; 43 required formatting. Full build validation remains pending.
- Previous local normal/LTO builds completed with exit 0; executable hashes match
  their metadata. They predate the upstream merge/formatting and do not validate
  current sources. Provenance/logs: `runtime/Build/w1-resume-20261016/`.
  Launch records describe original refs; build-info records refs at completion.
- Gameplay, target NVIDIA behavior, long-session resource pressure and performance
  remain untested. See [UPSTREAM_6D2A7388.md](UPSTREAM_6D2A7388.md) before revisiting
  excluded shader/upload paths; merge ancestry does not mean they were enabled.
