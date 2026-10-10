"""One-off source patch: Shadow Preset row above the three shadow options."""
p = 'D:/i3-pc/runtime/src/core/i3/menu.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)


rep('''constexpr std::array<u32, 3> ShadowDetailIndices{0, 300, 1000};
''', '''constexpr std::array<u32, 3> ShadowDetailIndices{0, 300, 1000};
// Shadow presets: sun rate, light rate, detail.
constexpr std::array<const char*, 4> ShadowPresetNames{"Original", "Balanced", "Fast", "Off"};
constexpr std::array<std::array<int, 3>, 4> ShadowPresets{{
    {0, 0, 0},
    {1, 1, 1},
    {1, 2, 2},
    {2, 2, 0},
}};

/// Index of the shadow preset matching the three options, or -1 for a custom mix.
int CurrentShadowPreset() {
    for (size_t p = 0; p < ShadowPresets.size(); p++) {
        if (ShadowPresets[p] == std::array<int, 3>{shadow_rate[0], shadow_rate[1], shadow_detail}) {
            return static_cast<int>(p);
        }
    }
    return -1;
}
''')
rep('''        rows.push_back({"Sun Shadows", ShadowRateNames[shadow_rate[0]],''',
    '''        const int shadow_preset = CurrentShadowPreset();
        rows.push_back({"Shadow Preset",
                        shadow_preset < 0 ? "Custom" : ShadowPresetNames[shadow_preset],
                        "Sets the three shadow options below. Original keeps the game's picture",
                        true});
        rows.push_back({"Sun Shadows", ShadowRateNames[shadow_rate[0]],''')
rep('''        } else if (const int kind = row - 9 - static_cast<int>(effects.size());
                   kind >= 0 && kind < static_cast<int>(shadow_rate.size())) {''',
    '''        } else if (const int kind = row - 10 - static_cast<int>(effects.size()); kind == -1) {
            const int count = static_cast<int>(ShadowPresets.size());
            const auto& preset =
                ShadowPresets[(std::max(CurrentShadowPreset(), 0) + step + count) % count];
            shadow_rate = {preset[0], preset[1]};
            shadow_detail = preset[2];
            ApplyEffects();
            SaveEffects();
        } else if (kind >= 0 && kind < static_cast<int>(shadow_rate.size())) {''')
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
