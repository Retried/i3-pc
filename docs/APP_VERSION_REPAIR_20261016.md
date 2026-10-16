# Local merged-dump APP_VER repair (2026-10-16)

## Cause and correction

The emulator correctly reads APP_VER from the mounted param.sfo. The installed
CUSA00004 merged dump had APP_VER=01.00 and VERSION=01.07. Inspection of the
local merged package's unencrypted SFO entry found the same bytes and fields;
the installed SFO was not an overlay-selection or parsing error.

The package identifies the merged release as 1.07, its changeinfo starts with
app_ver=01.07 (Graphics Bug Fixes), PUBTOOLINFO records c_date=20180219 and
sdk_ver=04008000, and the executable reports compiled SDK 0x4008061. Together
these corroborate the merged release's intended version and its stale APP_VER.
This evidence goes beyond treating VERSION alone as the installed update.

At the user's request, APP_VER was corrected to 01.07 in the local extracted
`E:/Games/iss/CUSA00004/sce_sys/param.sfo`. Exactly one byte changed, offset 776,
from ASCII 0 to ASCII 7. The complete original was backed up before the write,
and the new bytes were read back and checked. The original package was not
modified. No emulator version override, title-specific parsing rule, executable
patch, game download or update installation was introduced.

| Item | SHA-256 |
| --- | --- |
| Original SFO (1,668 bytes) | `83D2D30FF4D913E5D72D1DE99C4F4DB526AAC1E2242220C6D98837C348979A89` |
| Corrected SFO (1,668 bytes) | `5FC0401A62DEB7AF516638FFC5413CDA3DE8B63BCBF9B3DB8BECA19C15C5C417` |
| Unchanged eboot.bin | `2D1CA79630D7BBE6FA29575F59AA7996D43071D74AC8E4F7D40137967D9039AB` |

## Verification and recovery

An isolated run on AMD Ryzen 5 7640HS and NVIDIA GeForce RTX 4050 Laptop GPU
used the existing CI baseline executable. Its log reports both
`App Version: 01.07` and `GPU_Model: NVIDIA GeForce RTX 4050 Laptop GPU`.
The scripted run exited with code 0 at 13:48 Warsaw time. It verifies version
identification and startup, not full gameplay acceptance or the then-pending W2
build. The later successful candidate build and control runs are recorded in
[W2_NVIDIA_VULKAN.md](W2_NVIDIA_VULKAN.md) and [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md).

Local backup and machine-readable records are under the ignored directory
`runtime/Build/w2-nvidia-20261016/`:

- `param.sfo.before-appver-repair`: complete original SFO.
- `game-metadata-before.json`: installed/package metadata comparison and hashes.
- `appver-repair.json`: before/after hashes, changed offset and verification.
- `inspect-game-metadata.py`, `repair-game-appver.py`: exact local operations.
- `appver-nvidia/`: launch/status, screenshots and emulator log.

To restore the original metadata if needed:

```powershell
Copy-Item -LiteralPath 'E:\Ziutkowanie\i3-pc\runtime\Build\w2-nvidia-20261016\param.sfo.before-appver-repair' -Destination 'E:\Games\iss\CUSA00004\sce_sys\param.sfo'
```

No game data or backup is committed to Git. This is a correction of this
corroborated merged dump's identification, not a general rule to replace
APP_VER with VERSION. Other dumps need their own provenance or a proper update
dump; changing metadata does not upgrade their executable or assets.
