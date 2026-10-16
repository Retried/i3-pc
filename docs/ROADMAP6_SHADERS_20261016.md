# Roadmap item 6: shader correctness

## Scope

Implemented the required ports, adapted to runtime base
`f88d3b6f331272ce854bda5875c11386b180f94f` and the existing local changes:

- [#5348](https://github.com/shadps4-emu/shadPS4/pull/5348): distinguish indirect
  draws in runtime information and unbias vertex/instance IDs independently
  of whether the draw copies the base into an SGPR.
- [#5346](https://github.com/shadps4-emu/shadPS4/pull/5346): separate translations
  for V_LOG_CLAMP_F32, V_RCP_CLAMP_F32, V_RSQ_CLAMP_F32 and V_RSQ_LEGACY_F32.
- [#5342](https://github.com/shadps4-emu/shadPS4/pull/5342): expand the fp64
  opcode switch used by shader information collection, following the final
  upstream revision rather than its superseded generic type-walking draft.

Downloaded PR patch series are retained in `runtime/Build/roadmap6-20261016/`.
They include review revisions; the final upstream commit identifiers and
intake rationale are listed in [UPSTREAM_SHADPS4_20261016.md](UPSTREAM_SHADPS4_20261016.md).
Items 1-5 and earlier local optimizations are retained.

## Indirect IDs and local cache integration

DrawIndirectParams carries an explicitly default-false is_indirect flag. The
guest indirect path sets it to true, including host direct commands emitted
from checked guest indirect arguments. BuildRuntimeInfo copies it into the
software vertex-stage state for ordinary VS, export VS and local VS paths.
The prologue subtracts BaseVertex/BaseInstance for indirect draws when fetch
shader data does not already account for the corresponding base. Existing
SGPR writes and fetch/base assertions are retained.

- SwVertexRuntimeInfo's default equality includes the new flag; RuntimeInfo
  compares the active software stage and StageSpecialization compares runtime
  information. Program::FindPermutation, including its last-specialization
  shortcut, therefore distinguishes direct and indirect variants.
- VariantKey still hashes the serialized specialization by content. RuntimeInfo
  is zero-initialized by Initialize before fields are populated, retaining
  deterministic padding for the raw serialization and content hashes.
- RefreshGraphicsKey still calls RefreshGraphicsStages before its target-state
  reuse and before the previous-pipeline shortcut. Stage hashes incorporate
  the variant key; preserved target state copies the refreshed stage hashes.
- The repeated-indirect path is unchanged. It is established only after a
  successful indirect draw and compares SGPR offsets, index capacity, argument
  stride/type and current command buffer. Liverpool marks intervening direct
  draws/other relevant state changes as invalidating it. Repeated draws cannot
  establish a new direct/indirect mode without refreshing the pipeline.

## CLAMP, LEGACY and NaN adaptation

The new CLAMP translations restrict infinite arithmetic results to signed
FLT_MAX. RSQ LEGACY applies that bound and selects positive zero when its
source equals zero, including negative zero, as in the final upstream port.
Ordinary RCP/RSQ/LOG and the existing RCP LEGACY translation are unchanged.

The local FPClamp backend uses numeric NMin/NMax; copying upstream's FPClamp
calls would turn NaN results into a finite bound. A translation-local
ClampToFinite helper instead uses ordered comparisons and selections. Both
comparisons are false for NaN, preserving the arithmetic result. Finite values
and signed zeros pass through, while positive/negative infinity select their
corresponding bounds. Shared min/max/saturate emitters, legacy NaN rules,
V_CVT_PK_U8_F32's explicit NaN-to-zero conversion and destination modifiers
are untouched. This preserves the requested local behavior without changing
other users of FPClamp. Console bit-pattern confirmation remains pending.

The finite-bound intent is consistent with AMD's description of CLAMP in the
[Southern Islands ISA reference](https://www.amd.com/content/dam/amd/en/documents/radeon-tech-docs/instruction-set-architectures/southern-islands-instruction-set-architecture.pdf).

## fp64 and serialization audit

Shader information collection now recognizes all 40 F64-typed operations in
the local ir/opcodes.inc, including pack/unpack, arithmetic, comparisons,
classification and conversions. This also covers operations with non-F64
results, such as FPFrexpExp64 and comparisons. The existing SPIR-V context uses
uses_fp64 to define double types, vectors and frexp result types; its policy
and device feature handling remain intact.

ShaderBinaryVersion changes from 7 to 9 for the combined code-generation ports.
ShaderMetaVersion changes from 6 to 7 because StageSpecialization serializes
RuntimeInfo as raw bytes: inserting is_indirect changes field meaning even if
the compiler retains the structure's total size. LoadShaderMeta checks both
versions before spec.Deserialize or info.Deserialize; incompatible metadata
therefore cannot reach the new raw reader or load an old SPIR-V module.
Compute and graphics warm-up both pass through this guard. PipelineKeyVersion
remains 3 because its serialized layout is unchanged. Existing content-based
variant naming and cache files are retained; incompatible entries are skipped
and rebuilt as needed rather than deleting user caches.

## Conditional ports

The shader and capture directories under dist/user currently have no opcode
captures to inventory. The available dist/user/log text logs contain no
IMAGE_GATHER4_C_L, UndefU64 or descriptor-patching failure evidence. These logs
are not a complete shader inventory and do not prove that the game never uses
those cases. Following the roadmap's evidence gate, the following remain
conditional rather than being silently promoted:

| Port | Disposition |
| --- | --- |
| #5344 gather | Not imported; requires a target-game shader/log occurrence. |
| #5366 U64 undefined | Not imported; requires a target-game shader/log occurrence. |
| #5352 descriptor pattern | Not imported. Its new BufferResource field and enum member would affect serialized Info buffer vectors and descriptor interpretation; a future port must audit/bump metadata again and verify discovery, patching, specialization and reload together. No BufferResource layout changes occur in this wave. |

## Validation and records

- Follow-up on the item-7 prompt: the full build completed with exit 0;
  executable present and SHA-256 verified as
  `E95763D8B48C956F9E970EB2709BE55131C8B2A776714F56CB9E0EE2489235FC`.
  Runtime acceptance remains pending.

- Previous item-5 Windows x64 Release/LTO build completed with exit 0, executable
  present and SHA-256 verified:
  `9FE18B5B371A6DEA77DF6DF1ADB3F6F1D1E3B86862884A550352C4665D244D9C`.
- Final Windows x64 clang-cl syntax checks passed with exit 0 for translate.cpp,
  vector_alu.cpp, shader_info_collection_pass.cpp, spirv_emit_context.cpp,
  vk_pipeline_cache.cpp, vk_pipeline_serialization.cpp and vk_rasterizer.cpp.
  Final diagnostic logs are empty. An initial typed-IR conversion diagnostic
  was corrected; initial records are retained separately. Changed-range
  clang-format checks and repository whitespace checks passed.
- Evidence directory: `runtime/Build/roadmap6-20261016/`; see syntax-launch.json,
  syntax-status.json, response files/logs, format-status.json, item6.diff and
  fp64-opcode-audit.json. The latter is a source inventory, not GPU validation.
- Full Windows x64 Release/LTO build launch: build-launch.json, with durable
  logs, source hashes, dirty state and build-status.json. Expected executable:
  `runtime/Build/roadmap6-x64-Clang-Release-lto/shadps4.exe`. Native log windows
  are recorded in syntax-console-launch.json and console-launch.json. No
  desktop input/activation automation is used.
- No tests were added, following runtime/AGENTS.md. No GPU shader execution,
  console reference run, game run, Vulkan validation or FPS gain is claimed.

## Pending OpenOrbis hardware cases to share

Share OpenOrbis samples that write guest shader results to a readable buffer;
record GCN, descriptors/registers, raw bit patterns and readback hashes on
console and on Windows AMD/NVIDIA. Keep validation separate from timing.

- Compare indexed/non-indexed direct, indirect and multi/count draws with
  nonzero first vertex/base vertex and first instance. Cover absent/present
  base SGPR copies, fetch shaders with/without base offsets, VS/ES/LS stages,
  instance step rates and positive/negative vertex offsets.
- Alternate direct and indirect draws using identical programs and otherwise
  identical registers, including zero SGPR offsets. Repeat indirect draws,
  then change SGPR offsets/index capacity or insert a direct draw; compare
  ordinary and repeated paths with recording worker enabled/disabled.
- For each new ALU translation compare positive/negative zero, small/large
  finite values, subnormals, signed infinities, quiet/signaling NaN and negative
  logarithm/square-root inputs. Cover ABS/NEG, output multiplier/clamp and
  DX10_CLAMP/denormal modes; compare finite bounds and NaN classification.
- Exercise standalone double arithmetic, comparisons, classification,
  conversions, frexp and pack/unpack. Check Float64 capability/type declarations
  and Vulkan/SPIR-V validation, including operations with integer/bool outputs.
- Reload caches written before this wave: metadata must be rejected before
  deserialization. Populate both direct/indirect variants in each encounter
  order, restart, then verify matching variants and no incompatible SPIR-V use.
- Run CUSA00004 v1.07 transitions, lighting/shadows, effects and save/load, with
  cold and warm caches. Console, Khronos-layer and gameplay acceptance remain
  pending; measurements, if later requested, follow BENCHMARK_PROTOCOL.md.
