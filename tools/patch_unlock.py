"""One-off source patch: 'Game Frame Limit' option on the in-game Graphics page."""
P = 'D:/i3-pc/runtime/src/core/i3/menu.cpp'
s = open(P, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
BS = chr(92)


def rep(a, b):
    global s
    assert a in s, a[:70]
    s = s.replace(a, b, 1)


rep('constexpr std::array<const char*, 3> PresetNames',
    '// The game\'s own Options > Video > Frame Rate ("30fps limit") is stored in each save. On by\n'
    '// default here: the limit is lifted whatever the save says.\n'
    'bool unlock_frame_rate = true;\n\n'
    'constexpr std::array<const char*, 3> PresetNames')
rep('''        if (!effect.on) {
            VideoCore::PassFilter::Skip(effect.fs_hash);
        }
    }
}''', '''        if (!effect.on) {
            VideoCore::PassFilter::Skip(effect.fs_hash);
        }
    }
    Common::g_unlock_flip_rate = unlock_frame_rate;
}''')
line = '        file << effect.key << " = " << (effect.on ? "on" : "off") << "' + BS + 'n";\n    }\n}'
rep(line, line[:-1] + '    file << "unlock_frame_rate = " << (unlock_frame_rate ? "on" : "off") << "' + BS + 'n";\n}')
rep('''        for (auto& effect : effects) {
            if (name == effect.key) {
                effect.on = value != "off";
            }
        }''', '''        for (auto& effect : effects) {
            if (name == effect.key) {
                effect.on = value != "off";
            }
        }
        if (name == "unlock_frame_rate") {
            unlock_frame_rate = value != "off";
        }''')
rep('''            rows.push_back({effect.label, effect.on ? "On" : "Off", effect.description, true});
        }
''', '''            rows.push_back({effect.label, effect.on ? "On" : "Off", effect.description, true});
        }
        rows.push_back({"Game Frame Limit", unlock_frame_rate ? "Unlimited" : "Game Setting",
                        "Unlimited lifts the game's own 30 FPS limit (Options > Video > Frame "
                        "Rate). Applies at once",
                        true});
''')
rep('''        if (row >= 8 && row < 8 + static_cast<int>(effects.size())) {
            effects[row - 8].on = !effects[row - 8].on;
            ApplyEffects();
            SaveEffects();
        }''', '''        if (row >= 8 && row < 8 + static_cast<int>(effects.size())) {
            effects[row - 8].on = !effects[row - 8].on;
            ApplyEffects();
            SaveEffects();
        } else if (row == 8 + static_cast<int>(effects.size())) {
            unlock_frame_rate = !unlock_frame_rate;
            ApplyEffects();
            SaveEffects();
        }''')
if '#include "common/recording.h"' not in s:
    i = s.index('#include "')
    s = s[:i] + '#include "common/recording.h"\n' + s[i:]
open(P, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
