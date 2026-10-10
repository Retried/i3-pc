"""One-off source patch: hook the in-game PC options menu into the runtime."""
ROOT = 'D:/i3-pc/runtime/'


def rw(path, pairs, includes=()):
    p = ROOT + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert a in s, (path, a[:70])
        s = s.replace(a, b, 1)
    for inc in includes:
        if inc not in s:
            i = s.index('#include "')
            s = s[:i] + inc + '\n' + s[i:]
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('CMakeLists.txt', [
    ('set(DEV_TOOLS src/core/devtools/layer.cpp\n',
     'set(DEV_TOOLS src/core/devtools/layer.cpp\n              src/core/i3/menu.cpp\n              src/core/i3/menu.h\n'),
])

# The overlay draws last, over everything else the layer shows.
rw('src/core/devtools/layer.cpp', [
    ('''                Text("Volume: %d", EmulatorSettings.GetVolumeSlider());
            }
            End();
        }
    }
''', '''                Text("Volume: %d", EmulatorSettings.GetVolumeSlider());
            }
            End();
        }
    }

    I3::Menu::Draw();
'''),
], includes=('#include "core/i3/menu.h"',))

rw('src/sdl_window.cpp', [
    ('''    if (ImGui::Core::ProcessEvent(&event)) {
        return;
    }
''', '''    if (ImGui::Core::ProcessEvent(&event)) {
        return;
    }
    // The PC options overlay takes input ahead of the game while it is open.
    if (I3::Menu::OnEvent(event)) {
        return;
    }
'''),
    ('''    case SDL_EVENT_TOGGLE_FRIENDS:
        ImGui::Friends::Toggle();
        break;
''', '''    case SDL_EVENT_TOGGLE_FRIENDS:
        // The friends hotkey (F2 by default) opens the PC options in the inFAMOUS build.
        if (Common::ElfInfo::Instance().GameSerial() == "CUSA00004") {
            I3::Menu::Toggle();
        } else {
            ImGui::Friends::Toggle();
        }
        break;
'''),
], includes=('#include "core/i3/menu.h"',))

rw('src/imgui/renderer/imgui_core.cpp', [
    ('''    // Big Picture
''', '''    // Condensed face for the PC options overlay of the inFAMOUS build (a Windows system
    // font; the default UI font is used when it is missing).
    for (const char* path :
         {"C:/Windows/Fonts/bahnschrift.ttf", "C:/Windows/Fonts/arialnb.ttf"}) {
        std::error_code ec;
        if (std::filesystem::exists(path, ec)) {
            ImFontConfig overlay_cfg{};
            overlay_cfg.OversampleH = 2;
            I3::Menu::SetFont(io.Fonts->AddFontFromFileTTF(path, 72.0f, &overlay_cfg));
            break;
        }
    }

    // Big Picture
'''),
], includes=('#include "core/i3/menu.h"', '#include <filesystem>'))

# Texture pack: reloadable after the icon sheet was redrawn.
rw('src/video_core/texture_cache/texture_cache.h', [
    ('extern std::atomic<PromptSet> g_prompt_set;\n',
     'extern std::atomic<PromptSet> g_prompt_set;\n/// Set after the replacement files changed on disk: they are read again and the images\n/// they replace are uploaded again.\nextern std::atomic<bool> g_pack_reload;\n'),
])
rw('src/video_core/texture_cache/texture_cache.cpp', [
    ('std::atomic<PromptSet> g_prompt_set{PromptSet::PlayStation};\n',
     'std::atomic<PromptSet> g_prompt_set{PromptSet::PlayStation};\nstd::atomic<bool> g_pack_reload{false};\nstatic std::atomic<bool> g_pack_files_stale{false};\n'),
    ('    static const auto packs = [] {\n', '    const auto load_packs = [] {\n'),
    ('''        return sets;
    }();
    const bool pack_empty''', '''        return sets;
    };
    static auto packs = load_packs();
    if (g_pack_files_stale.exchange(false)) {
        packs = load_packs();
    }
    const bool pack_empty'''),
    ('''    if (pack_applied_set != ActivePromptSet() && !pack_ranges.empty()) {
        pack_applied_set = ActivePromptSet();''', '''    const bool reload = g_pack_reload.exchange(false);
    if (reload) {
        g_pack_files_stale = true;
    }
    if ((reload || pack_applied_set != ActivePromptSet()) && !pack_ranges.empty()) {
        pack_applied_set = ActivePromptSet();'''),
])
print('patched')
