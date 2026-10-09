// SPDX-License-Identifier: GPL-2.0-or-later

#include <algorithm>
#include <cctype>
#include <array>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <SDL3/SDL.h>
#include <fmt/format.h>
#include <imgui.h>

#include "common/recording.h"
#include "core/i3/first_run.h"
#include "common/elf_info.h"
#include "common/logging/log.h"
#include "core/emulator_settings.h"
#include "core/i3/menu.h"
#include "common/path_util.h"
#include "input/input_handler.h"
#include "video_core/pass_filter.h"
#include "video_core/texture_cache/texture_cache.h"

#ifdef _WIN32
#include <windows.h>
#endif

namespace Input {
std::filesystem::path GetInputConfigFile(const std::string& game_id);
}

namespace Overlay {
void ToggleSimpleFps();
}

namespace I3::Menu {

namespace {

enum class Page { Main, Controls, Graphics };

std::atomic_bool open{false};
std::atomic_bool capturing{false};
Page page = Page::Main;
int selected = 0;
ImFont* menu_font = nullptr;
bool fps_shown = false;
// Set when an option that only takes effect at the next start was changed.
bool restart_note = false;

// The look of the game's own Options screen: black panel, yellow title, white condensed text.
constexpr ImU32 Yellow = IM_COL32(246, 190, 0, 255);
constexpr ImU32 White = IM_COL32(236, 236, 236, 255);
constexpr ImU32 Grey = IM_COL32(150, 150, 150, 255);
constexpr ImU32 Dim = IM_COL32(96, 96, 96, 255);

struct Action {
    const char* pad;   // output name in the binding file
    const char* label; // what the game calls it
};
constexpr std::array<Action, 26> Actions{{
    {"r2", "Main Attack"},
    {"l2", "Aim / Zoom"},
    {"r1", "Heavy Attack"},
    {"l1", "Special Power"},
    {"cross", "Jump"},
    {"circle", "Dash"},
    {"square", "Melee"},
    {"triangle", "Karmic Actions"},
    {"touchpad_center", "Touchpad Press (Drain, Interact)"},
    {"l3", "L3"},
    {"r3", "R3"},
    {"options", "Pause"},
    {"pad_up", "D-pad Up"},
    {"pad_down", "D-pad Down"},
    {"pad_left", "D-pad Left"},
    {"pad_right", "D-pad Right"},
    {"axis_left_y_minus", "Move Forward"},
    {"axis_left_y_plus", "Move Back"},
    {"axis_left_x_minus", "Move Left"},
    {"axis_left_x_plus", "Move Right"},
    {"motion_sideways", "Hold Controller Sideways (Spray Can)"},
    {"motion_shake", "Shake Controller"},
    {"touchpad_swipe_up", "Touchpad Swipe Up"},
    {"touchpad_swipe_down", "Touchpad Swipe Down"},
    {"touchpad_swipe_left", "Touchpad Swipe Left"},
    {"touchpad_swipe_right", "Touchpad Swipe Right"},
}};

bool IsMouseName(const std::string& name) {
    return name.ends_with("button") || name.starts_with("mousewheel");
}

std::filesystem::path BindingFile() {
    return Input::GetInputConfigFile(std::string(Common::ElfInfo::Instance().GameSerial()));
}

/// Splits "name = value" (comments and blank lines give an empty name).
std::pair<std::string, std::string> SplitLine(const std::string& line) {
    const auto strip = [](std::string text) {
        const auto first = text.find_first_not_of(" \t\r");
        if (first == std::string::npos) {
            return std::string{};
        }
        return text.substr(first, text.find_last_not_of(" \t\r") - first + 1);
    };
    const auto equals = line.find('=');
    if (equals == std::string::npos || strip(line).starts_with('#')) {
        return {};
    }
    return {strip(line.substr(0, equals)), strip(line.substr(equals + 1))};
}

/// A value that names a keyboard key or mouse input (not a controller pass-through line).
bool IsKeyboardValue(const std::string& value) {
    return Input::string_to_keyboard_key_map.contains(value);
}

std::vector<std::string> ReadLines() {
    std::vector<std::string> lines;
    std::ifstream file{BindingFile()};
    for (std::string line; std::getline(file, line);) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        lines.push_back(std::move(line));
    }
    return lines;
}

/// How a binding-file key name is shown to the player.
std::string DisplayName(const std::string& key) {
    static const std::vector<std::pair<const char*, const char*>> names{
        {"leftbutton", "Left Mouse"},     {"rightbutton", "Right Mouse"},
        {"middlebutton", "Middle Mouse"}, {"sidebuttonback", "Mouse 4"},
        {"sidebuttonforward", "Mouse 5"}, {"mousewheelup", "Wheel Up"},
        {"mousewheeldown", "Wheel Down"}, {"lshift", "Left Shift"},
        {"rshift", "Right Shift"},        {"lctrl", "Left Ctrl"},
        {"rctrl", "Right Ctrl"},          {"lalt", "Left Alt"},
        {"ralt", "Right Alt"},            {"escape", "Esc"},
        {"space", "Space"},               {"enter", "Enter"},
        {"tab", "Tab"},                   {"backspace", "Backspace"},
        {"up", "Up"},                     {"down", "Down"},
        {"left", "Left"},                 {"right", "Right"},
        {"capslock", "Caps Lock"},
    };
    for (const auto& [name, shown] : names) {
        if (key == name) {
            return shown;
        }
    }
    std::string upper = key;
    std::ranges::transform(upper, upper.begin(), [](unsigned char c) { return std::toupper(c); });
    return upper;
}

std::string KeysOf(const std::vector<std::string>& lines, const char* pad) {
    std::string keys;
    for (const auto& line : lines) {
        const auto [name, value] = SplitLine(line);
        if (name == pad && IsKeyboardValue(value)) {
            keys += (keys.empty() ? "" : ", ") + DisplayName(value);
        }
    }
    return keys.empty() ? "-" : keys;
}

/// Redraws the in-game button icons for the new bindings (the same script Keys.bat runs),
/// then has the runtime load and apply them.
void RefreshIcons() {
#ifdef _WIN32
    std::thread([] {
        wchar_t module_path[MAX_PATH]{};
        GetModuleFileNameW(nullptr, module_path, MAX_PATH);
        const auto dir = std::filesystem::path(module_path).parent_path();
        std::wstring command = L"pwsh -NoProfile -ExecutionPolicy Bypass -File \"" +
                               (dir / "Keys.ps1").wstring() + L"\" -Icons";
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        startup.dwFlags = STARTF_USESHOWWINDOW;
        startup.wShowWindow = SW_HIDE;
        PROCESS_INFORMATION process{};
        if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                           nullptr, dir.wstring().c_str(), &startup, &process)) {
            WaitForSingleObject(process.hProcess, 15000);
            CloseHandle(process.hThread);
            CloseHandle(process.hProcess);
            VideoCore::g_pack_reload = true;
        } else {
            LOG_ERROR(Input, "PC menu: could not run Keys.ps1 to redraw the icons, error {}",
                      GetLastError());
        }
    }).detach();
#endif
}

/// Binds `pad` to the single input `key`, applies the bindings and redraws the icons.
void Bind(const char* pad, const std::string& key) {
    auto lines = ReadLines();
    size_t insert_at = lines.size();
    for (size_t i = lines.size(); i-- > 0;) {
        const auto [name, value] = SplitLine(lines[i]);
        if (name == pad && IsKeyboardValue(value)) {
            lines.erase(lines.begin() + i);
            insert_at = i;
        }
    }
    if (insert_at == lines.size()) {
        // Not bound before: ahead of the controller section.
        for (size_t i = 0; i < lines.size(); i++) {
            if (lines[i].starts_with("# --- Controller")) {
                insert_at = i;
                break;
            }
        }
    }
    lines.insert(lines.begin() + insert_at, fmt::format("{} = {}", pad, key));
    {
        std::ofstream file{BindingFile(), std::ios::trunc | std::ios::binary};
        for (const auto& line : lines) {
            file << line << "\n";
        }
    }
    Input::ParseInputConfig(std::string(Common::ElfInfo::Instance().GameSerial()));
    RefreshIcons();
}

/// Binding-file name of the input in `event`, or empty.
std::string NameOf(const SDL_Event& event) {
    u32 code = 0;
    bool mouse = false;
    if (event.type == SDL_EVENT_KEY_DOWN) {
        code = event.key.key;
    } else if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN) {
        code = event.button.button;
        mouse = true;
    } else if (event.type == SDL_EVENT_MOUSE_WHEEL) {
        return event.wheel.y > 0 ? "mousewheelup" : event.wheel.y < 0 ? "mousewheeldown" : "";
    } else {
        return {};
    }
    for (const auto& [name, value] : Input::string_to_keyboard_key_map) {
        if (value == code && IsMouseName(name) == mouse && !name.starts_with("mousewheel")) {
            return name;
        }
    }
    return {};
}

SDL_Window* Window() {
    const auto id = static_cast<SDL_WindowID>(
        reinterpret_cast<uintptr_t>(ImGui::GetMainViewport()->PlatformHandle));
    return SDL_GetWindowFromID(id);
}

// ---- Graphics options ----

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
// The game's own Options > Video > Frame Rate ("30fps limit") is stored in each save. On by
// default here: the limit is lifted whatever the save says.
bool unlock_frame_rate = true;

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
    Common::g_unlock_flip_rate = unlock_frame_rate;
}

void SaveEffects() {
    std::ofstream file{EffectsFile(), std::ios::trunc};
    for (const auto& effect : effects) {
        file << effect.key << " = " << (effect.on ? "on" : "off") << "\n";
    }
    file << "unlock_frame_rate = " << (unlock_frame_rate ? "on" : "off") << "\n";
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
        if (name == "unlock_frame_rate") {
            unlock_frame_rate = value != "off";
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

constexpr std::array<u32, 6> FrameCaps{30, 60, 90, 120, 144, 1000};
constexpr std::array<std::pair<u32, u32>, 4> WindowSizes{
    {{1280, 720}, {1920, 1080}, {2560, 1440}, {3840, 2160}}};
constexpr std::array<const char*, 4> SharpenNames{"Off", "Low", "Medium", "High"};
// RCAS attenuation in thousandths: lower is sharper.
constexpr std::array<int, 4> SharpenValues{0, 600, 250, 100};

template <typename Range, typename Value>
int IndexOf(const Range& range, const Value& value, int fallback) {
    const auto it = std::ranges::find(range, value);
    return it == range.end() ? fallback : static_cast<int>(it - range.begin());
}

int SharpenIndex() {
    if (!EmulatorSettings.IsRcasEnabled()) {
        return 0;
    }
    return IndexOf(SharpenValues, static_cast<int>(EmulatorSettings.GetRcasAttenuation()), 2);
}

struct Row {
    std::string label;
    std::string value;
    std::string description;
    bool adjustable = false;
};

std::vector<Row> BuildRows() {
    std::vector<Row> rows;
    if (page == Page::Main) {
        rows.push_back({"CONTROLS", "", "Change the keyboard and mouse bindings"});
        rows.push_back({"GRAPHICS", "", "Frame rate, display and image options"});
        rows.push_back({"RESUME", "", "Return to the game"});
        rows.push_back({"QUIT GAME", "", "Close the game"});
    } else if (page == Page::Controls) {
        const auto lines = ReadLines();
        for (const auto& action : Actions) {
            rows.push_back({action.label, KeysOf(lines, action.pad),
                            "Confirm, then press the key or mouse button to use"});
        }
        rows.push_back({"BACK", "", "Return to the previous menu"});
    } else {
        const u32 cap = EmulatorSettings.GetVblankFrequency();
        rows.push_back({"Frame Rate Cap", cap >= 1000 ? "Uncapped" : fmt::format("{}", cap),
                        "Applies the next time the game starts", true});
        rows.push_back({"VSync", EmulatorSettings.GetPresentMode() == "Fifo" ? "On" : "Off",
                        "Applies the next time the game starts", true});
        rows.push_back({"Fullscreen", EmulatorSettings.IsFullScreen() ? "On" : "Off",
                        "Applies at once", true});
        rows.push_back({"Window Size",
                        fmt::format("{} x {}", EmulatorSettings.GetWindowWidth(),
                                    EmulatorSettings.GetWindowHeight()),
                        "Applies at once when not in fullscreen", true});
        rows.push_back({"Upscaling (FSR)", EmulatorSettings.IsFsrEnabled() ? "On" : "Off",
                        "Scales the 1080p picture to the window. Applies at once", true});
        rows.push_back({"Sharpening", SharpenNames[SharpenIndex()],
                        "Sharpening pass of the upscaler. Applies at once", true});
        rows.push_back({"Frame Rate Counter", fps_shown ? "On" : "Off", "Applies at once", true});
        const int preset = CurrentPreset();
        rows.push_back({"Effects Preset", preset < 0 ? "Custom" : PresetNames[preset],
                        "Original keeps every effect; Sharp drops anti-aliasing; Minimal drops all",
                        true});
        for (const auto& effect : effects) {
            rows.push_back({effect.label, effect.on ? "On" : "Off", effect.description, true});
        }
        rows.push_back({"Game Frame Limit", unlock_frame_rate ? "Unlimited" : "Game Setting",
                        "Unlimited lifts the game's own 30 FPS limit (Options > Video > Frame "
                        "Rate). Applies at once",
                        true});
        rows.push_back({"BACK", "", "Return to the previous menu"});
    }
    return rows;
}

void AdjustGraphics(int row, int step) {
    switch (row) {
    case 0: {
        const int index = IndexOf(FrameCaps, EmulatorSettings.GetVblankFrequency(), 1);
        const int count = static_cast<int>(FrameCaps.size());
        EmulatorSettings.SetVblankFrequency(FrameCaps[(index + step + count) % count]);
        restart_note = true;
        break;
    }
    case 1:
        EmulatorSettings.SetPresentMode(EmulatorSettings.GetPresentMode() == "Fifo" ? "Immediate"
                                                                                     : "Fifo");
        restart_note = true;
        break;
    case 2: {
        const bool on = !EmulatorSettings.IsFullScreen();
        EmulatorSettings.SetFullScreen(on);
        EmulatorSettings.SetFullScreenMode(on ? "Fullscreen (Borderless)" : "Windowed");
        if (SDL_Window* window = Window()) {
            SDL_SetWindowFullscreen(window, on);
        }
        break;
    }
    case 3: {
        const std::pair<u32, u32> current{EmulatorSettings.GetWindowWidth(),
                                          EmulatorSettings.GetWindowHeight()};
        const int index = IndexOf(WindowSizes, current, 1);
        const int count = static_cast<int>(WindowSizes.size());
        const auto [width, height] = WindowSizes[(index + step + count) % count];
        EmulatorSettings.SetWindowWidth(width);
        EmulatorSettings.SetWindowHeight(height);
        if (SDL_Window* window = Window(); window && !EmulatorSettings.IsFullScreen()) {
            SDL_SetWindowSize(window, static_cast<int>(width), static_cast<int>(height));
        }
        break;
    }
    case 4:
        EmulatorSettings.SetFsrEnabled(!EmulatorSettings.IsFsrEnabled());
        break;
    case 5: {
        const int count = static_cast<int>(SharpenValues.size());
        const int index = (SharpenIndex() + step + count) % count;
        EmulatorSettings.SetRcasEnabled(index != 0);
        if (index != 0) {
            EmulatorSettings.SetRcasAttenuation(SharpenValues[index]);
        }
        break;
    }
    case 6:
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
        } else if (row == 8 + static_cast<int>(effects.size())) {
            unlock_frame_rate = !unlock_frame_rate;
            ApplyEffects();
            SaveEffects();
        }
        return;
    }
    EmulatorSettings.Save();
}

/// direction: 0 = confirm, -1 / +1 = left / right.
void Activate(int row, int direction, int count) {
    if (page == Page::Main) {
        if (direction != 0) {
            return;
        }
        if (row == 0) {
            page = Page::Controls;
            selected = 0;
        } else if (row == 1) {
            page = Page::Graphics;
            selected = 0;
        } else if (row == 2) {
            open = false;
        } else {
            SDL_Event quit{};
            quit.type = SDL_EVENT_QUIT;
            SDL_PushEvent(&quit);
        }
    } else if (row == count - 1) {
        if (direction == 0) {
            page = Page::Main;
            selected = page == Page::Main ? 0 : selected;
            selected = 0;
        }
    } else if (page == Page::Controls) {
        if (direction == 0) {
            capturing = true;
        }
    } else {
        AdjustGraphics(row, direction == 0 ? 1 : direction);
    }
}

ImFont* MenuFont() {
    return menu_font ? menu_font : ImGui::GetFont();
}

ImVec2 TextSize(float size, const std::string& text) {
    return MenuFont()->CalcTextSizeA(size, FLT_MAX, 0.0f, text.c_str());
}

void Text(ImDrawList* draw, float size, ImVec2 pos, ImU32 color, const std::string& text) {
    draw->AddText(MenuFont(), size, pos, color, text.c_str());
}

/// One "[key] LABEL" hint, right aligned at `right_x`. Returns the width used.
float Hint(ImDrawList* draw, float right_x, float y, float scale, const char* keyboard,
           const char* pad, const char* label) {
    const bool keys = VideoCore::ActivePromptSet() == VideoCore::PromptSet::Keyboard;
    const char* name = keys ? keyboard : pad;
    const float size = 24.0f * scale;
    const float label_width = TextSize(size, label).x;
    const float cap_height = 30.0f * scale;
    const float cap_width =
        std::max(cap_height, TextSize(size * 0.85f, name).x + 18.0f * scale);
    const float label_x = right_x - label_width;
    const float cap_x = label_x - 10.0f * scale - cap_width;
    draw->AddRectFilled({cap_x, y}, {cap_x + cap_width, y + cap_height}, White,
                        keys ? 6.0f * scale : cap_height * 0.5f);
    const ImVec2 name_size = TextSize(size * 0.85f, name);
    Text(draw, size * 0.85f,
         {cap_x + (cap_width - name_size.x) * 0.5f, y + (cap_height - name_size.y) * 0.5f},
         IM_COL32(16, 16, 16, 255), name);
    Text(draw, size, {label_x, y + (cap_height - TextSize(size, label).y) * 0.5f}, White, label);
    return label_width + cap_width + 34.0f * scale;
}

} // namespace

void SetFont(ImFont* font) {
    menu_font = font;
}

ImFont* Font() {
    return MenuFont();
}

void Toggle() {
    if (!open) {
        page = Page::Main;
        selected = 0;
    }
    capturing = false;
    open = !open;
}

bool IsOpen() {
    return open;
}

bool OnEvent(const SDL_Event& event) {
    if (FirstRun::IntroActive()) {
        // Nothing reaches the game, or this menu, while the opening lines play.
        return event.type != SDL_EVENT_KEY_UP && event.type != SDL_EVENT_MOUSE_BUTTON_UP &&
               event.type != SDL_EVENT_GAMEPAD_BUTTON_UP && event.type != SDL_EVENT_QUIT;
    }
    if (!open) {
        return false;
    }
    switch (event.type) {
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_WHEEL:
        // The key that opened the overlay closes it; it does not reach the hotkey layer while
        // the overlay holds the input.
        if (!capturing && event.type == SDL_EVENT_KEY_DOWN && event.key.key == SDLK_F2 &&
            !event.key.repeat) {
            Toggle();
            return true;
        }
        if (capturing) {
            capturing = false;
            // Escape leaves the binding as it was.
            if (event.type == SDL_EVENT_KEY_DOWN && event.key.key == SDLK_ESCAPE) {
                return true;
            }
            const std::string name = NameOf(event);
            if (!name.empty() && page == Page::Controls && selected >= 0 &&
                selected < static_cast<int>(Actions.size())) {
                Bind(Actions[selected].pad, name);
            }
        }
        return true;
    case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
    case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    case SDL_EVENT_MOUSE_MOTION:
        return true;
    default:
        // Releases still reach the game, so nothing held when the menu opened stays held.
        return false;
    }
}

void Draw() {
    using namespace ImGui;

    static const bool enabled = Common::ElfInfo::Instance().GameSerial() == "CUSA00004";
    if (!enabled) {
        return;
    }
    static const bool effects_loaded = (LoadEffects(), true);
    FirstRun::DrawIntro();
    if (FirstRun::IntroActive()) {
        return;
    }
    const bool pad_combo =
        (IsKeyDown(ImGuiKey_GamepadL3) && IsKeyPressed(ImGuiKey_GamepadR3, false)) ||
        (IsKeyDown(ImGuiKey_GamepadR3) && IsKeyPressed(ImGuiKey_GamepadL3, false));
    if (pad_combo) {
        Toggle();
    }
    if (!open) {
        return;
    }

    const std::vector<Row> rows = BuildRows();
    const int count = static_cast<int>(rows.size());
    selected = std::clamp(selected, 0, count - 1);
    int activate_row = -1, activate_direction = 0;
    bool back = false;
    // While a key is being captured the keys below must not act on the menu as well.
    static bool was_capturing = false;
    const bool skip_input = capturing || was_capturing;
    was_capturing = capturing;
    if (!skip_input) {
        if (IsKeyPressed(ImGuiKey_DownArrow) || IsKeyPressed(ImGuiKey_GamepadDpadDown) ||
            IsKeyPressed(ImGuiKey_S)) {
            selected = (selected + 1) % count;
        }
        if (IsKeyPressed(ImGuiKey_UpArrow) || IsKeyPressed(ImGuiKey_GamepadDpadUp) ||
            IsKeyPressed(ImGuiKey_W)) {
            selected = (selected + count - 1) % count;
        }
        if (IsKeyPressed(ImGuiKey_Enter, false) || IsKeyPressed(ImGuiKey_Space, false) ||
            IsKeyPressed(ImGuiKey_GamepadFaceDown, false)) {
            activate_row = selected;
        } else if (IsKeyPressed(ImGuiKey_LeftArrow) || IsKeyPressed(ImGuiKey_GamepadDpadLeft) ||
                   IsKeyPressed(ImGuiKey_A)) {
            activate_row = selected;
            activate_direction = -1;
        } else if (IsKeyPressed(ImGuiKey_RightArrow) || IsKeyPressed(ImGuiKey_GamepadDpadRight) ||
                   IsKeyPressed(ImGuiKey_D)) {
            activate_row = selected;
            activate_direction = 1;
        }
        back = IsKeyPressed(ImGuiKey_Escape, false) || IsKeyPressed(ImGuiKey_Backspace, false) ||
               IsKeyPressed(ImGuiKey_GamepadFaceRight, false);
    }

    // Laid out like the game's Options screen: a black panel on the left with a yellow title.
    const ImVec2 display = GetIO().DisplaySize;
    const float scale = display.y / 1080.0f;
    auto* draw = GetForegroundDrawList();
    draw->AddRectFilled({0.0f, 0.0f}, display, IM_COL32(0, 0, 0, 150));
    const ImVec2 panel_min{display.x * 0.16f, display.y * 0.09f};
    const ImVec2 panel_max{display.x * 0.84f, display.y * 0.91f};
    draw->AddRectFilled(panel_min, panel_max, IM_COL32(8, 8, 8, 236));
    draw->AddRect(panel_min, panel_max, IM_COL32(220, 220, 220, 255), 0.0f, 0, 2.0f * scale);
    const float left = panel_min.x + 44.0f * scale;
    const float right = panel_max.x - 44.0f * scale;
    float y = panel_min.y + 28.0f * scale;
    const char* title = page == Page::Main       ? "PC OPTIONS"
                        : page == Page::Controls ? "CONTROLS"
                                                 : "GRAPHICS";
    Text(draw, 64.0f * scale, {left, y}, Yellow, title);
    y += 92.0f * scale;

    const float row_height = 44.0f * scale;
    const float text_size = 32.0f * scale;
    const float footer = 150.0f * scale;
    const int visible =
        std::max(1, static_cast<int>((panel_max.y - footer - y) / row_height));
    // Keep the selection in view on long pages.
    static int first = 0;
    if (count <= visible) {
        first = 0;
    } else {
        first = std::clamp(first, std::max(0, selected - visible + 1), selected);
        first = std::min(first, count - visible);
    }
    const ImVec2 mouse = GetIO().MousePos;
    const bool mouse_moved = GetIO().MouseDelta.x != 0.0f || GetIO().MouseDelta.y != 0.0f;
    for (int i = first; i < std::min(count, first + visible); i++) {
        const Row& row = rows[i];
        const float row_y = y + row_height * (i - first);
        const bool hovered = mouse.x >= left && mouse.x <= right && mouse.y >= row_y &&
                             mouse.y < row_y + row_height;
        if (hovered && !skip_input) {
            if (mouse_moved) {
                selected = i;
            }
            if (IsMouseClicked(ImGuiMouseButton_Left)) {
                selected = i;
                activate_row = i;
                activate_direction = 0;
            }
        }
        const bool current = i == selected;
        if (current) {
            draw->AddRectFilled({left - 14.0f * scale, row_y}, {right + 14.0f * scale, row_y + row_height},
                                IM_COL32(246, 190, 0, 38));
        }
        const ImU32 color = current ? Yellow : White;
        const float text_y = row_y + (row_height - TextSize(text_size, row.label).y) * 0.5f;
        Text(draw, text_size, {left, text_y}, color, row.label);
        std::string value = row.value;
        if (current && capturing) {
            value = "PRESS A KEY...";
        } else if (row.adjustable && current) {
            value = "<  " + value + "  >";
        }
        if (!value.empty()) {
            Text(draw, text_size, {right - TextSize(text_size, value).x, text_y},
                 current ? Yellow : Grey, value);
        }
    }
    if (count > visible) {
        // Scroll position.
        const float track_top = y;
        const float track_height = row_height * visible;
        const float bar_height = track_height * visible / count;
        const float bar_y = track_top + (track_height - bar_height) * first / (count - visible);
        draw->AddRectFilled({right + 22.0f * scale, track_top},
                            {right + 26.0f * scale, track_top + track_height}, Dim);
        draw->AddRectFilled({right + 22.0f * scale, bar_y},
                            {right + 26.0f * scale, bar_y + bar_height}, White);
    }

    const Row& current_row = rows[selected];
    const float note_y = panel_max.y - 128.0f * scale;
    Text(draw, 26.0f * scale, {left, note_y}, Grey,
         capturing ? "Press the key or mouse button for this action. Esc keeps the current one."
                   : current_row.description);
    if (restart_note && page == Page::Graphics) {
        Text(draw, 26.0f * scale, {left, note_y + 34.0f * scale}, Yellow,
             "Frame rate cap and VSync changes take effect the next time the game starts.");
    }
    float hint_x = right;
    const float hint_y = panel_max.y - 52.0f * scale;
    hint_x -= Hint(draw, hint_x, hint_y, scale, "ESC", "O", "BACK");
    if (current_row.adjustable) {
        hint_x -= Hint(draw, hint_x, hint_y, scale, "A  D", "D-PAD", "CHANGE");
    } else {
        hint_x -= Hint(draw, hint_x, hint_y, scale, "ENTER", "X", "SELECT");
    }
    Hint(draw, hint_x, hint_y, scale, "F2", "L3+R3", "CLOSE");

    if (activate_row >= 0) {
        Activate(activate_row, activate_direction, count);
    } else if (back) {
        if (page == Page::Main) {
            open = false;
        } else {
            page = Page::Main;
            selected = 0;
        }
    }
}

} // namespace I3::Menu
