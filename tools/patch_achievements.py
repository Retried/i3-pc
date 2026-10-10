"""One-off source patch: achievements hook, menu page and test action."""
R = 'D:/i3-pc/runtime/'


def rw(path, pairs, head=None):
    p = R + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:60], s.count(a))
        s = s.replace(a, b, 1)
    if head and head.split('\n')[-1] not in s:
        i = s.index('#include')
        s = s[:i] + head + '\n' + s[i:]
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('CMakeLists.txt', [
    ('              src/core/i3/first_run.cpp\n',
     '              src/core/i3/achievements.cpp\n              src/core/i3/achievements.h\n'
     '              src/core/i3/first_run.cpp\n'),
])

rw('src/core/libraries/np/np_trophy.cpp', [
    ('''    s32 handle_index = handle - 1;
    if (handle_index >= trophy_handles.Size() ||
        !trophy_handles.IsAllocated({static_cast<u32>(handle_index)})) {
        return ORBIS_NP_TROPHY_ERROR_INVALID_HANDLE;
    }

    ContextKey contextkey = trophy_contexts[contextId];
    const auto& ctx = contexts_internal[contextkey];
    if (!ctx.registered)
        return ORBIS_NP_TROPHY_ERROR_NOT_REGISTERED;
    const auto& xml_dir = ctx.xml_dir;
    const auto& trophy_file = ctx.trophy_xml_path;
''', '''    s32 handle_index = handle - 1;
    if (handle_index >= trophy_handles.Size() ||
        !trophy_handles.IsAllocated({static_cast<u32>(handle_index)})) {
        return ORBIS_NP_TROPHY_ERROR_INVALID_HANDLE;
    }

    if (Common::ElfInfo::Instance().GameSerial() == "CUSA00004") {
        // The trophy package cannot be decrypted without a console key: the achievement list
        // of the build takes the unlock.
        *platinumId = ORBIS_NP_TROPHY_INVALID_TROPHY_ID;
        switch (I3::Achievements::Unlock(trophyId)) {
        case I3::Achievements::UnlockResult::AlreadyUnlocked:
            return ORBIS_NP_TROPHY_ERROR_TROPHY_ALREADY_UNLOCKED;
        case I3::Achievements::UnlockResult::UnknownId:
            return ORBIS_NP_TROPHY_ERROR_INVALID_TROPHY_ID;
        default:
            return ORBIS_OK;
        }
    }

    ContextKey contextkey = trophy_contexts[contextId];
    const auto& ctx = contexts_internal[contextkey];
    if (!ctx.registered)
        return ORBIS_NP_TROPHY_ERROR_NOT_REGISTERED;
    const auto& xml_dir = ctx.xml_dir;
    const auto& trophy_file = ctx.trophy_xml_path;
'''),
], head='#include "common/elf_info.h"\n#include "core/i3/achievements.h"')

rw('src/core/i3/menu.cpp', [
    ('enum class Page { Main, Controls, Graphics };', 'enum class Page { Main, Controls, Graphics, Achievements };'),
    ('''        rows.push_back({"GRAPHICS", "", "Frame rate, display and image options"});
''', '''        rows.push_back({"GRAPHICS", "", "Frame rate, display and image options"});
        rows.push_back({"ACHIEVEMENTS",
                        fmt::format("{} / {}", Achievements::UnlockedCount(), Achievements::Count()),
                        "Trophies of the game unlocked in this build"});
'''),
    ('''    } else if (page == Page::Controls) {
        const auto lines = ReadLines();''', '''    } else if (page == Page::Achievements) {
        for (int id = 0; id < Achievements::Count(); id++) {
            const u64 when = Achievements::UnlockedAt(id);
            std::string state = "Locked";
            if (when != 0) {
                const std::time_t time = static_cast<std::time_t>(when);
                char text[32]{};
                std::strftime(text, sizeof(text), "%Y-%m-%d", std::localtime(&time));
                state = fmt::format("Unlocked {}", text);
            }
            rows.push_back({Achievements::Name(id), state, Achievements::Description(id)});
        }
        rows.push_back({"BACK", "", "Return to the previous menu"});
    } else if (page == Page::Controls) {
        const auto lines = ReadLines();'''),
    ('''        } else if (row == 1) {
            page = Page::Graphics;
            selected = 0;
        } else if (row == 2) {
            open = false;
        } else {''', '''        } else if (row == 1) {
            page = Page::Graphics;
            selected = 0;
        } else if (row == 2) {
            page = Page::Achievements;
            selected = 0;
        } else if (row == 3) {
            open = false;
        } else {'''),
    ('''    } else if (page == Page::Controls) {
        if (direction == 0) {
            capturing = true;
        }
    } else {
        AdjustGraphics(row, direction == 0 ? 1 : direction);''', '''    } else if (page == Page::Controls) {
        if (direction == 0) {
            capturing = true;
        }
    } else if (page == Page::Achievements) {
        // A list to read: nothing to change.
    } else {
        AdjustGraphics(row, direction == 0 ? 1 : direction);'''),
    ('''    const char* title = page == Page::Main       ? "PC OPTIONS"
                        : page == Page::Controls ? "CONTROLS"
                                                 : "GRAPHICS";''',
     '''    const char* title = page == Page::Main           ? "PC OPTIONS"
                        : page == Page::Controls     ? "CONTROLS"
                        : page == Page::Achievements ? "ACHIEVEMENTS"
                                                     : "GRAPHICS";'''),
], head='#include <ctime>\n#include "core/i3/achievements.h"')

rw('src/sdl_window.cpp', [
    ('''        } else if (action.starts_with("key=")) {''',
     '''        } else if (action.starts_with("ach=")) {
            // Test aid: "ach=5" unlocks achievement 5 as the game would.
            I3::Achievements::Unlock(std::stoi(action.substr(4)));
        } else if (action.starts_with("key=")) {'''),
], head='#include "core/i3/achievements.h"')
print('patched')
