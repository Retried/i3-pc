"""One-off source patch: start screen at launch, one pause menu on the Options button with the
game's own Options screen inside it, Return to Main Menu in place of Quit during play."""
R = 'D:/i3-pc/runtime/src/'


def rw(path, pairs, head=None):
    p = R + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b, 1)
    if head and head.split('\n')[-1] not in s:
        i = s.index('#include')
        s = s[:i] + head + '\n' + s[i:]
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('core/i3/menu.h', [
    ('''// The PC options overlay of the inFAMOUS Second Son build: key bindings and display settings,
// drawn over the running game. F2, or L3 + R3 on a controller, opens and closes it.''',
     '''// The menus of the inFAMOUS Second Son build. The game itself has no main menu (it loads the
// last save at once) and draws its Options screen itself, so lines cannot be added to it:
// - a start screen at launch: Continue, New Game, Load Game, Controls, Graphics,
//   Achievements, Quit;
// - one pause menu on the Options button (Esc), holding the game's own Options screen next to
//   Controls, Graphics, Achievements and Return to Main Menu.'''),
    ('void Toggle();\n', '''void Toggle();
/// The pad's Options button, after the binding layer. Returns true when the menu took it (it
/// opens or closes the pause menu) and the game must not see it.
bool OnOptionsButton(bool pressed);
'''),
])

rw('input/input_handler.cpp', [
    ('''        default: // is a normal key (hopefully)
            controller->Button(SDLGamepadToOrbisButton(button), new_button_state);''',
     '''        default: // is a normal key (hopefully)
            if (button == SDL_GAMEPAD_BUTTON_START && I3::Menu::OnOptionsButton(new_button_state)) {
                break;
            }
            controller->Button(SDLGamepadToOrbisButton(button), new_button_state);'''),
], head='#include "core/i3/menu.h"')

MENU = [
    ('enum class Page { Main, Controls, Graphics, Achievements };',
     'enum class Page { Main, Controls, Graphics, Achievements, Start };'),
    ('''// QUIT GAME asks once more: set by the first press, cleared when the selection moves.
bool quit_armed = false;
int quit_armed_row = -1;
''', '''// Quit and Return to Main Menu ask once more: set by the first press, cleared when the
// selection moves.
bool quit_armed = false;
int quit_armed_row = -1;
// The page the sub-pages go back to: the start screen at launch, the pause menu during play.
Page home = Page::Main;
// The start screen, shown once per launch when the game presents its first frame.
enum class StartState { Unknown, Showing, Done };
StartState start_state = StartState::Unknown;
bool has_saves = false;
// The game is held (its threads paused) while a menu is up.
bool game_held = false;
u64 opened_ms = 0;
bool options_consumed = false;
// Pad presses sent to the game later: opening its own Options screen for the player.
struct TimedPress {
    u64 at_ms;
    Libraries::Pad::OrbisPadButtonDataOffset button;
    bool down;
};
std::vector<TimedPress> timed_presses;
std::mutex timed_mutex;
// New Game / Load Game on the start screen: the row of the game's Options screen to open at
// once the last save has loaded, -1 for none.
int pending_game_row = -1;
u64 pending_ready_ms = 0;
'''),
    ('''/// direction: 0 = confirm, -1 / +1 = left / right.
void Activate(int row, int direction, int count) {
    if (page == Page::Main) {''', '''void HoldGame(bool hold) {
    if (hold && !game_held) {
        DebugState.PauseGuestThreads();
    } else if (!hold && game_held) {
        DebugState.ResumeGuestThreads();
    }
    game_held = hold;
}

void Press(u64 delay_ms, Libraries::Pad::OrbisPadButtonDataOffset button, u64 hold_ms = 150) {
    const u64 now = SDL_GetTicks();
    std::scoped_lock lock{timed_mutex};
    timed_presses.push_back({now + delay_ms, button, true});
    timed_presses.push_back({now + delay_ms + hold_ms, button, false});
}

void RunTimedPresses() {
    const u64 now = SDL_GetTicks();
    std::scoped_lock lock{timed_mutex};
    auto* controller = (*Common::Singleton<Input::GameControllers>::Instance())[0];
    std::erase_if(timed_presses, [&](const TimedPress& press) {
        if (now < press.at_ms) {
            return false;
        }
        controller->Button(press.button, press.down);
        return true;
    });
}

/// True when a save of the game exists for any user of this profile.
bool HasSaves() {
    std::error_code ec;
    const auto home_dir = Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "home";
    for (const auto& user : std::filesystem::directory_iterator(home_dir, ec)) {
        const auto saves = user.path() / "savedata" / "CUSA00004";
        for (const auto& entry : std::filesystem::directory_iterator(saves, ec)) {
            if (entry.is_directory(ec)) {
                return true;
            }
        }
    }
    return false;
}

/// The game cannot go back to a menu by itself: the program starts again at the start screen.
void ReturnToMainMenu() {
    auto* mnt = Common::Singleton<Core::FileSys::MntPoints>::Instance();
    const auto eboot = mnt->GetHostPath("/app0/eboot.bin");
    LOG_INFO(Input, "PC menu: returning to the start screen");
    Common::Singleton<Core::Emulator>::Instance()->Restart(eboot);
}

void LeaveStartScreen(int game_row) {
    start_state = StartState::Done;
    home = Page::Main;
    open = false;
    pending_game_row = game_row;
    pending_ready_ms = 0;
}

/// Confirm on a row of the start screen or of the pause menu.
void ActivateTop(const std::string& label, int row) {
    using Libraries::Pad::OrbisPadButtonDataOffset;
    const bool needs_confirm = label == "QUIT" || label == "RETURN TO MAIN MENU";
    if (needs_confirm && !(quit_armed && quit_armed_row == row)) {
        quit_armed = true;
        quit_armed_row = row;
        return;
    }
    quit_armed = false;
    if (label == "CONTINUE") {
        LeaveStartScreen(-1);
    } else if (label == "NEW GAME") {
        LeaveStartScreen(has_saves ? 1 : -1);
    } else if (label == "LOAD GAME") {
        LeaveStartScreen(2);
    } else if (label == "RESUME") {
        open = false;
    } else if (label == "GAME OPTIONS") {
        open = false;
        Press(300, OrbisPadButtonDataOffset::Options);
    } else if (label == "CONTROLS") {
        page = Page::Controls;
        selected = 0;
    } else if (label == "GRAPHICS") {
        page = Page::Graphics;
        selected = 0;
    } else if (label == "ACHIEVEMENTS") {
        page = Page::Achievements;
        selected = 0;
    } else if (label == "QUIT") {
        SDL_Event quit{};
        quit.type = SDL_EVENT_QUIT;
        SDL_PushEvent(&quit);
    } else if (label == "RETURN TO MAIN MENU") {
        ReturnToMainMenu();
    }
}

/// direction: 0 = confirm, -1 / +1 = left / right.
void Activate(int row, int direction, int count) {
    if (page == Page::Main) {'''),
    ('''        if (direction == 0) {
            page = Page::Main;
            selected = page == Page::Main ? 0 : selected;
            selected = 0;
        }''', '''        if (direction == 0) {
            page = home;
            selected = 0;
        }'''),
    # Rows of the two top pages.
    ('''    if (page == Page::Main) {
        rows.push_back({"CONTROLS", "", "Change the keyboard and mouse bindings"});
        rows.push_back({"GRAPHICS", "", "Frame rate, display and image options"});
        rows.push_back({"ACHIEVEMENTS",
                        fmt::format("{} / {}", Achievements::UnlockedCount(), Achievements::Count()),
                        "Trophies of the game unlocked in this build"});
        rows.push_back({"RESUME", "", "Return to the game"});
        rows.push_back({"QUIT GAME", quit_armed ? "Press again to quit" : "",
                        quit_armed ? "Unsaved progress since the last checkpoint is lost"
                                   : "Close the game"});''',
     '''    if (page == Page::Main || page == Page::Start) {
        const std::string trophies =
            fmt::format("{} / {}", Achievements::UnlockedCount(), Achievements::Count());
        if (page == Page::Start) {
            if (has_saves) {
                rows.push_back({"CONTINUE", "", "Carry on from your last save"});
                rows.push_back({"NEW GAME", "",
                                "Your last save loads first; the game's Options screen then "
                                "opens on New Game"});
                rows.push_back({"LOAD GAME", "",
                                "Your last save loads first; the game's Options screen then "
                                "opens on Load Game"});
            } else {
                rows.push_back({"NEW GAME", "", "Start the game"});
            }
        } else {
            rows.push_back({"RESUME", "", "Return to the game"});
            rows.push_back({"GAME OPTIONS", "",
                            "The game's own screen: save, new game, load game, difficulty, sound, "
                            "subtitles"});
        }
        rows.push_back({"CONTROLS", "", "Change the keyboard and mouse bindings"});
        rows.push_back({"GRAPHICS", "", "Frame rate, display and image options"});
        rows.push_back({"ACHIEVEMENTS", trophies, "Trophies of the game unlocked in this build"});
        if (page == Page::Start) {
            rows.push_back({"QUIT", quit_armed ? "Press again to quit" : "", "Close the game"});
        } else {
            rows.push_back({"RETURN TO MAIN MENU", quit_armed ? "Press again to confirm" : "",
                            quit_armed ? "Progress since the last checkpoint is lost, and the game "
                                         "loads again (about 40 seconds)"
                                       : "Back to the start screen. Quit is there"});
        }'''),
    ('''void Toggle() {
    if (!open) {
        page = Page::Main;
        selected = 0;
    }
    capturing = false;
    open = !open;
}''', '''void Toggle() {
    if (start_state == StartState::Showing) {
        return; // the start screen closes through its own rows
    }
    if (!open) {
        page = Page::Main;
        home = Page::Main;
        selected = 0;
        opened_ms = SDL_GetTicks();
    }
    capturing = false;
    open = !open;
}

bool OnOptionsButton(bool pressed) {
    static const bool enabled = Common::ElfInfo::Instance().GameSerial() == "CUSA00004";
    if (!enabled) {
        return false;
    }
    if (FirstRun::IntroActive() || start_state == StartState::Showing) {
        return true;
    }
    if (pressed) {
        Toggle();
        options_consumed = true;
        return true;
    }
    if (options_consumed) {
        options_consumed = false;
        return true;
    }
    return false;
}'''),
    ('''    const bool pad_combo =
        (IsKeyDown(ImGuiKey_GamepadL3) && IsKeyPressed(ImGuiKey_GamepadR3, false)) ||
        (IsKeyDown(ImGuiKey_GamepadR3) && IsKeyPressed(ImGuiKey_GamepadL3, false));
    if (pad_combo) {
        Toggle();
    }
    if (!open) {
        return;
    }
''', '''    if (start_state == StartState::Unknown) {
        // Test runs go straight into the game unless they ask for the start screen.
        static const bool skip = std::getenv("SOTC_HEADLESS") != nullptr &&
                                 std::getenv("I3_START_SCREEN") == nullptr;
        if (skip) {
            start_state = StartState::Done;
        } else if (g_first_flip_ms.load(std::memory_order_relaxed) != 0) {
            start_state = StartState::Showing;
            has_saves = HasSaves();
            page = Page::Start;
            home = Page::Start;
            selected = 0;
            opened_ms = SDL_GetTicks();
            open = true;
        }
    }
    RunTimedPresses();
    if (pending_game_row >= 0 && Common::g_save_mounts.load() >= 3) {
        // The last save has loaded (the game mounts its saves again once it is in play): open
        // the game's Options screen and move to the row that was asked for.
        const u64 now = SDL_GetTicks();
        if (pending_ready_ms == 0) {
            pending_ready_ms = now;
        } else if (now - pending_ready_ms > 5000) {
            using Libraries::Pad::OrbisPadButtonDataOffset;
            Press(0, OrbisPadButtonDataOffset::Options);
            for (int i = 0; i < pending_game_row; i++) {
                Press(1800 + 400 * i, OrbisPadButtonDataOffset::Down, 120);
            }
            pending_game_row = -1;
        }
    }
    const bool pad_combo =
        (IsKeyDown(ImGuiKey_GamepadL3) && IsKeyPressed(ImGuiKey_GamepadR3, false)) ||
        (IsKeyDown(ImGuiKey_GamepadR3) && IsKeyPressed(ImGuiKey_GamepadL3, false));
    if (pad_combo) {
        Toggle();
    }
    HoldGame(open);
    if (!open) {
        return;
    }
'''),
    ('''    if (quit_armed && (page != Page::Main || selected != quit_armed_row)) {
        quit_armed = false;
    }''', '''    if (quit_armed && ((page != Page::Main && page != Page::Start) || selected != quit_armed_row)) {
        quit_armed = false;
    }'''),
    ('''    const bool skip_input = capturing || was_capturing;''',
     '''    // The key press that opened the menu must not act on it as well.
    const bool skip_input = capturing || was_capturing || SDL_GetTicks() - opened_ms < 250;'''),
    ('''        back = IsKeyPressed(ImGuiKey_Escape, false) || IsKeyPressed(ImGuiKey_Backspace, false) ||
               IsKeyPressed(ImGuiKey_GamepadFaceRight, false);''',
     '''        back = IsKeyPressed(ImGuiKey_Escape, false) || IsKeyPressed(ImGuiKey_Backspace, false) ||
               IsKeyPressed(ImGuiKey_GamepadFaceRight, false) ||
               IsKeyPressed(ImGuiKey_GamepadStart, false);'''),
    ('''    draw->AddRectFilled({0.0f, 0.0f}, display, IM_COL32(0, 0, 0, 150));''',
     '''    // The start screen stands on black; the pause menu dims the game behind it.
    draw->AddRectFilled({0.0f, 0.0f}, display, IM_COL32(0, 0, 0, home == Page::Start ? 255 : 150));'''),
    ('''    const char* title = page == Page::Main           ? "PC OPTIONS"
                        : page == Page::Controls     ? "CONTROLS"''',
     '''    const char* title = page == Page::Main           ? "PAUSED"
                        : page == Page::Start        ? "inFAMOUS SECOND SON"
                        : page == Page::Controls     ? "CONTROLS"'''),
    ('''    Hint(draw, hint_x, hint_y, scale, "F2", "L3+R3", "CLOSE");

    if (activate_row >= 0) {
        Activate(activate_row, activate_direction, count);
    } else if (back) {
        if (page == Page::Main) {
            open = false;
        } else {
            page = Page::Main;
            selected = 0;
        }
    }''', '''
    if (activate_row >= 0) {
        if (page == Page::Main || page == Page::Start) {
            if (activate_direction == 0) {
                ActivateTop(rows[activate_row].label, activate_row);
            }
        } else {
            Activate(activate_row, activate_direction, count);
        }
    } else if (back) {
        if (page == Page::Main) {
            open = false;
        } else if (page != Page::Start) {
            page = home;
            selected = 0;
        }
    }'''),
    ('''namespace Input {
std::filesystem::path GetInputConfigFile(const std::string& game_id);
}''', '''namespace Input {
std::filesystem::path GetInputConfigFile(const std::string& game_id);
}

// Set by the video output when the game presents its first frame.
extern std::atomic<u64> g_first_flip_ms;'''),
]
rw('core/i3/menu.cpp', MENU,
   head='#include "common/singleton.h"\n#include "core/debug_state.h"\n#include "core/file_sys/fs.h"\n'
        '#include "core/libraries/pad/pad.h"\n#include "emulator.h"\n#include "input/controller.h"')
print('patched')
