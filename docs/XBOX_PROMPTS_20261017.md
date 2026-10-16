# Xbox button prompts

## Investigation

The wrapper is on `main`; `runtime` is detached at
`f88d3b6f331272ce854bda5875c11386b180f94f`, also contained in `origin/runtime`.
The pre-existing dirty roadmap changes were preserved. The preceding roadmap-8
Windows Release/LTO job completed with exit 0 and its executable was present.

`WindowSDL::WaitEvent` observes SDL keyboard/mouse and controller activity.
`VideoCore::ActivePromptSet` selects the texture set. `TextureCache::RefreshImage`
calls `ApplyTexturePack` after the normal guest image upload. It hashes the guest
bytes with `HashSparseMemory` and looks for hash-named replacement files in
`user/sotc_textures`, `keyboard` and `xbox`. Existing `.bin` files contain untiled
texture bytes, optionally a mip chain. The game retains control of UVs, sizes,
positions, animation, blending and shaders. Its font renderer is not involved.

Pack files are cached in CPU memory. Images recognized by any pack are tracked
by guest address; a style change invalidates those images in the existing cache
maintenance step. Their normal refresh restores the guest texture before applying
the selected pack. PlayStation uses the original guest textures.

`dist/Keys.ps1` already contained partial Xbox labels, SDL already selected Xbox
for non-PlayStation devices, and the cache already loaded an Xbox folder. However,
the generator required a private `glyphs/atlas_original.raw`, copied untouched
game artwork into its output, mislabeled touchpad press as View, and provided no
live style setting. The repository does not contain that private atlas or verified
hash mappings for separate 128x128 prompt images. The script documents bounds for
the 512x512 atlas `7824aa19ec8ef328`, and a separate keyboard Controls diagram.

## Implementation and modified files

| File | Change |
| --- | --- |
| `runtime/src/video_core/texture_cache/texture_cache.h` | Add Auto/PlayStation/Xbox/Keyboard style API; retain existing prompt sets. |
| `runtime/src/video_core/texture_cache/texture_cache.cpp` | Live style and persistence in existing `force.txt`; cached sparse atlas patches; title guard; style invalidation fix. |
| `runtime/src/sdl_window.cpp` | Startup and meaningful activity detection before overlays consume events; recognized Xbox families select Xbox, other pads retain PlayStation; disconnect fallback. |
| `runtime/src/core/i3/menu.cpp` | Add Button Prompts under Controls, preserve binding row indices, report persistence failures, use A/B in overlay hints. |
| `dist/XboxPrompts.ps1` | Generate original monochrome glyph patches and preview without game data. |
| `dist/Keys.ps1` | Delegate Xbox generation; leave keyboard drawing unchanged. |
| `tools/package-windows.ps1` | Include generator and generate Xbox assets before package manifest construction. |
| `dist/README.txt` | Document selection, deployment and coverage. |
| `docs/DECISIONS.md`, `docs/HANDOFF.md`, this report | Rationale, pending checks and evidence. |

The setting accepts the previous `keyboard`, `xbox`, `playstation` values, plus
`auto`. Missing/unknown values select Auto. It is read once; menu changes persist
before publishing the new atomic style. Editing the file externally requires a
restart. A failed write keeps the active in-memory style and shows an error.
Input bindings and gameplay processing are unchanged, including gesture emulation.
Small stick movement and controller sensor noise do not change the detected style.
Unknown/generic devices can use the explicit Xbox setting.

Xbox patches cover Cross=A, Circle=B, Square=X, Triangle=Y, L1=LB, R1=RB,
L2=LT, R2=RT, L3=LS, R3=RS and Options=the three-bar Menu symbol in the known
atlas cells. Colors remain monochrome to match the existing UI. Touchpad, motion,
D-pad and unverified cells remain guest artwork. No View substitute is generated.

The `.patch` format is little-endian: `I3P1`, u32 width/height/count, followed by
u32 x/y/width/height and bottom-up RGBA8 bytes for each rectangle. The loader limits
file size/count/bounds and requires the known atlas hash, 512x512 and RGBA8
UNORM/sRGB. Rectangles update mip zero through `Runtime::UploadImage`; no shader,
pipeline, format conversion or new renderer is introduced. All bytes and copy
descriptions are cached on load/reload; the upload copy list has inline capacity
64. Unchanged frames do not trigger prompt uploads. Normal guest texture updates
still refresh replacements. No performance measurements or FPS claims were made.

Unknown glyph capture now requires `SOTC_DUMP_UNKNOWN_GLYPHS`; explicit
`SOTC_TEXDUMP` still works. Otherwise merely installing the Xbox pack would enable
the old automatic readback/`scheduler.Finish` on every newly seen unknown glyph.

For an unpackaged executable, run `XboxPrompts.ps1 -OutputDirectory <exe-folder>`
before startup. The default output is beside the script. Windows packages do this
automatically. `Keys.ps1 -Icons` also regenerates Xbox patches and removes only
the legacy generated Xbox atlas `.bin`. Restart after installing assets into an
already running build. Generated Xbox graphics use the generator's GPL-2.0-or-later
license; no game pixels or commercial SDK graphics are distributed.

## Validation

- PowerShell parser checks passed for both generators and packaging script.
- Xbox generator executed on Windows: 21 disjoint in-bounds rectangles, 150648
  bytes, 37574 atlas texels. Binary structure, labels, row inversion and untouched
  touchpad bounds passed offline checks. Preview was visually inspected.
- Patch SHA256: `A6FB74AE8E50F2C04B4584332DA7DD75130FCBA0574E80667F27A7BDEB59FA6C`.
- Keyboard generator ran with the same bindings and synthetic transparent atlas
  before/after this change. Both outputs matched byte-for-byte: atlas SHA256
  `571299E8AD3B4F46762AB6ABE315C808BBDC31427747E18E66E9C9E0BDB901D3`, diagram
  `DEBC78BC005C1C87050B8F6D14DA8B435B52E1425A0BA58F215E8FE584E57CE9`.
  This checks generator compatibility, not actual guest rendering.
- Changed C++ files passed clang-format checks. Runtime rules prohibit adding
  repository tests; offline checks used ignored build scratch data.
- Windows x64 Release/LTO validation launch:
  `runtime/Build/xbox-20261017/build-launch.json`. It incrementally reuses the
  completed roadmap-8 build directory, preserving the prior executable/metadata
  in the new record directory. The job completed with exit 0, and the executable
  was present with matching SHA256
  `5454EF744091890C7DCB59ED3166369ADF3D27A4D8711C4AC96F8E2C7966EC2C`.
  The worker confirmed its source snapshot did not change during the build.
  No game was launched for this feature.

## Remaining acceptance and limitations

1. Retain the successful build record as compilation evidence; game acceptance
   remains separate from compilation.
2. On Windows 10/11, AMD Ryzen/NVIDIA Vulkan and CUSA00004 v1.07, launch with an
   Xbox One S controller already connected. In Auto, check A/B/X/Y, shoulders,
   triggers, stick clicks and Menu; inspect prompt size, orientation and alpha
   edges at supported display scales. Check gameplay, pause/confirm dialogs and
   context-dependent variants. A hash match does not prove every context uses
   this atlas; unrecognized textures intentionally retain originals.
3. Switch among all four styles using mouse, keyboard and controller in Controls.
   Confirm labels change without disturbing adjacent bindings or Language, leave
   the menu and verify all resident prompts update and PlayStation restores.
   Restart for each saved setting, including a legacy force.txt, missing/invalid
   value and an unwritable configuration directory.
4. Test Xbox/PlayStation switching, mouse movement/wheel, unplug/replug, multiple
   pads, idle stick/trigger noise and an unknown pad with the explicit override.
5. Rebind keyboard actions; check the existing keycaps and keyboard Controls
   diagram on screen. The private keyboard atlas dependency is pre-existing and
   is not supplied or reconstructed by this feature.
6. Check touchpad press, swipes, two fingers and spray-can motion instructions.
   They must keep their original meaning and artwork. D-pad, the controller
   diagram, separate 128x128 prompts and atlas mips beyond level zero are not converted.
   Verified mappings/layout evidence is required to extend those cases.
7. Run Vulkan core/synchronization validation when a Khronos layer is available;
   check guest texture refresh/restoration and rapid style changes. Observe that
   stable gameplay does not continually upload prompt data. Performance claims
   require BENCHMARK_PROTOCOL measurements; none have been made here.

Controller detection, style persistence through the actual UI, GPU uploads,
restoration, hotplug and performance have not been runtime-validated. This is a
bounded atlas implementation, not a claim of complete Xbox artwork coverage.
