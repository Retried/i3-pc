"""One-off source patch: per-effect switches and presets on the in-game Graphics page."""
P = 'D:/i3-pc/runtime/src/core/i3/menu.cpp'
s = open(P, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert a in s, a[:70]
    s = s.replace(a, b, 1)


rep('#include "input/input_handler.h"\n',
    '#include "common/path_util.h"\n#include "input/input_handler.h"\n#include "video_core/pass_filter.h"\n')

rep('// ---- Graphics options ----\n', '''// ---- Graphics options ----

// Effects the engine has no switch for: each is one fullscreen pass of the renderer, found by
// skipping passes one at a time in a frozen scene, and is turned off by not issuing its draws.
struct Effect {
    const char* label;
    const char* key; // name in the settings file
    u64 fs_hash;     // fragment shader of the pass
    const char* description;
    bool on = true;
};
std::array<Effect, 3> effects{{
    {"Anti-Aliasing", "antialiasing", 0x961c93ba,
     "Edge smoothing pass. Off gives a sharper picture with visible stair-steps. Applies at once"},
    {"Wet Surface Reflections", "reflections", 0x9215a6e8,
     "Reflections on wet ground and puddles. Applies at once"},
    {"Light Glow", "glow", 0x6d29fb0f, "Glow around fires and bright lights. Applies at once"},
}};
constexpr std::array<const char*, 3> PresetNames{"Original", "Sharp", "Minimal"};
// Which effects each preset keeps on, in the order of `effects`.
constexpr std::array<std::array<bool, 3>, 3> Presets{{
    {true, true, true},
    {false, true, true},
    {false, false, false},
}};

std::filesystem::path EffectsFile() {
    return Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "i3_graphics.txt";
}

void ApplyEffects() {
    VideoCore::PassFilter::Clear();
    for (const auto& effect : effects) {
        if (!effect.on) {
            VideoCore::PassFilter::Skip(effect.fs_hash);
        }
    }
}

void SaveEffects() {
    std::ofstream file{EffectsFile(), std::ios::trunc};
    for (const auto& effect : effects) {
        file << effect.key << " = " << (effect.on ? "on" : "off") << "\\n";
    }
}

void LoadEffects() {
    std::ifstream file{EffectsFile()};
    for (std::string line; std::getline(file, line);) {
        const auto [name, value] = SplitLine(line);
        for (auto& effect : effects) {
            if (name == effect.key) {
                effect.on = value != "off";
            }
        }
    }
    ApplyEffects();
}

/// Index of the preset matching the current switches, or -1 for a custom mix.
int CurrentPreset() {
    for (size_t p = 0; p < Presets.size(); p++) {
        bool same = true;
        for (size_t e = 0; e < effects.size(); e++) {
            same &= effects[e].on == Presets[p][e];
        }
        if (same) {
            return static_cast<int>(p);
        }
    }
    return -1;
}
''')

rep('''        rows.push_back({"Frame Rate Counter", fps_shown ? "On" : "Off", "Applies at once", true});
''', '''        rows.push_back({"Frame Rate Counter", fps_shown ? "On" : "Off", "Applies at once", true});
        const int preset = CurrentPreset();
        rows.push_back({"Effects Preset", preset < 0 ? "Custom" : PresetNames[preset],
                        "Original keeps every effect; Sharp drops anti-aliasing; Minimal drops all",
                        true});
        for (const auto& effect : effects) {
            rows.push_back({effect.label, effect.on ? "On" : "Off", effect.description, true});
        }
''')

rep('''    case 6:
        fps_shown = !fps_shown;
        Overlay::ToggleSimpleFps();
        return;
    default:
        return;
    }''', '''    case 6:
        fps_shown = !fps_shown;
        Overlay::ToggleSimpleFps();
        return;
    case 7: {
        const int count = static_cast<int>(Presets.size());
        const int preset = (std::max(CurrentPreset(), 0) + step + count) % count;
        for (size_t e = 0; e < effects.size(); e++) {
            effects[e].on = Presets[preset][e];
        }
        ApplyEffects();
        SaveEffects();
        return;
    }
    default:
        if (row >= 8 && row < 8 + static_cast<int>(effects.size())) {
            effects[row - 8].on = !effects[row - 8].on;
            ApplyEffects();
            SaveEffects();
        }
        return;
    }''')

# The saved switches take effect from the first frame, not only once the menu is opened.
rep('''    static const bool enabled = Common::ElfInfo::Instance().GameSerial() == "CUSA00004";
    if (!enabled) {
        return;
    }
''', '''    static const bool enabled = Common::ElfInfo::Instance().GameSerial() == "CUSA00004";
    if (!enabled) {
        return;
    }
    static const bool effects_loaded = (LoadEffects(), true);
''')

s = s.replace('"\\\\n";', '"\\n";')
open(P, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
