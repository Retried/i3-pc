// SPDX-License-Identifier: GPL-2.0-or-later

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <fmt/format.h>
#include <imgui.h>

#include "common/logging/log.h"
#include "common/path_util.h"
#include "core/debug_state.h"
#include "core/emulator_settings.h"
#include "core/i3/first_run.h"
#include "core/i3/menu.h"

#ifdef _WIN32
#include <windows.h>
#include <dxgi.h>
#pragma comment(lib, "dxgi")
#endif

// Set by the video output when the game presents its first frame.
extern std::atomic<u64> g_first_flip_ms;

namespace I3::FirstRun {

namespace {

std::filesystem::path UserFile(const char* name) {
    return Common::FS::GetUserPath(Common::FS::PathType::UserDir) / name;
}

struct System {
    u32 display_width = 1920;
    u32 display_height = 1080;
    u32 refresh_hz = 60;
    u32 cores = 4;
    u64 ram_mb = 8192;
    u64 vram_mb = 0;
    std::string gpu = "unknown";
};

System Detect() {
    System system;
    system.cores = std::max(1u, std::thread::hardware_concurrency() / 2);
#ifdef _WIN32
    DEVMODEW mode{};
    mode.dmSize = sizeof(mode);
    if (EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &mode)) {
        system.display_width = mode.dmPelsWidth;
        system.display_height = mode.dmPelsHeight;
        if (mode.dmDisplayFrequency > 1) {
            system.refresh_hz = mode.dmDisplayFrequency;
        }
    }
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    if (GlobalMemoryStatusEx(&memory)) {
        system.ram_mb = memory.ullTotalPhys >> 20;
    }
    // Physical cores, not logical processors.
    DWORD length = 0;
    GetLogicalProcessorInformationEx(RelationProcessorCore, nullptr, &length);
    if (length != 0) {
        std::string buffer(length, '\0');
        auto* info = reinterpret_cast<SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(buffer.data());
        if (GetLogicalProcessorInformationEx(RelationProcessorCore, info, &length)) {
            u32 cores = 0;
            for (DWORD offset = 0; offset < length;) {
                const auto* entry = reinterpret_cast<SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(
                    buffer.data() + offset);
                cores += entry->Relationship == RelationProcessorCore;
                offset += entry->Size;
            }
            if (cores != 0) {
                system.cores = cores;
            }
        }
    }
    // The adapter with the most dedicated memory is the one games run on.
    IDXGIFactory1* factory = nullptr;
    if (SUCCEEDED(CreateDXGIFactory1(__uuidof(IDXGIFactory1),
                                     reinterpret_cast<void**>(&factory)))) {
        IDXGIAdapter1* adapter = nullptr;
        for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; i++) {
            DXGI_ADAPTER_DESC1 desc{};
            if (SUCCEEDED(adapter->GetDesc1(&desc)) &&
                !(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) &&
                (desc.DedicatedVideoMemory >> 20) > system.vram_mb) {
                system.vram_mb = desc.DedicatedVideoMemory >> 20;
                std::string name;
                for (const wchar_t c : desc.Description) {
                    if (c == 0) {
                        break;
                    }
                    name += c < 128 ? static_cast<char>(c) : '?';
                }
                system.gpu = name;
            }
            adapter->Release();
        }
        factory->Release();
    }
#endif
    return system;
}

} // namespace

namespace {
bool fresh_install = false;
} // namespace

void NoteExistingSettings() {
    std::error_code ec;
    fresh_install = !std::filesystem::exists(UserFile("config.json"), ec) &&
                    !std::filesystem::exists(UserFile("i3_graphics.txt"), ec);
}

void AdjustSettings() {
    // Automated test runs leave the first-run steps for the player's own first start.
    if (std::getenv("I3_SKIP_FIRST_RUN") != nullptr) {
        return;
    }
    const auto marker = UserFile("i3_first_run.txt");
    std::error_code ec;
    if (std::filesystem::exists(marker, ec) && std::getenv("I3_FORCE_FIRST_RUN") == nullptr) {
        return;
    }
    if (!fresh_install && std::getenv("I3_FORCE_FIRST_RUN") == nullptr) {
        // Settings were here before this start: they are the player's, leave them alone.
        std::ofstream{marker, std::ios::trunc}
            << "Existing settings were found on the first start and kept as they were."
            << std::endl;
        return;
    }
    const System system = Detect();

    // The game renders 1080p; the window takes the display's size (the largest listed size
    // that fits), borderless fullscreen, with the upscaler bridging the difference.
    constexpr std::array<std::pair<u32, u32>, 4> sizes{
        {{1280, 720}, {1920, 1080}, {2560, 1440}, {3840, 2160}}};
    std::pair<u32, u32> window = sizes[0];
    for (const auto& size : sizes) {
        if (size.first <= system.display_width && size.second <= system.display_height) {
            window = size;
        }
    }
    const bool upscale = window.second > 1080;

    // Frame clock: the display's refresh rate among the offered caps, 60 on weak processors
    // (the game's frame rate is bound by one render thread; a faster clock only helps when
    // there is CPU to spare).
    constexpr std::array<u32, 5> caps{30, 60, 90, 120, 144};
    u32 cap = 60;
    if (system.cores >= 6) {
        for (const u32 candidate : caps) {
            if (candidate <= system.refresh_hz) {
                cap = candidate;
            }
        }
        cap = std::max(cap, 60u);
    }

    // Effects: everything on a mid-range PC or better, anti-aliasing off below that, all three
    // off on integrated or very small GPUs.
    const char* preset = "original";
    bool effects_on[3] = {true, true, true};
    if (system.vram_mb < 3000 || system.cores < 4) {
        preset = "minimal";
        effects_on[0] = effects_on[1] = effects_on[2] = false;
    } else if (system.vram_mb < 6000) {
        preset = "sharp";
        effects_on[0] = false;
    }

    EmulatorSettings.SetWindowWidth(window.first);
    EmulatorSettings.SetWindowHeight(window.second);
    EmulatorSettings.SetFullScreen(true);
    EmulatorSettings.SetFullScreenMode("Fullscreen (Borderless)");
    EmulatorSettings.SetFsrEnabled(upscale);
    EmulatorSettings.SetVblankFrequency(cap);
    EmulatorSettings.Save();
    {
        std::ofstream effects{UserFile("i3_graphics.txt"), std::ios::trunc};
        effects << "antialiasing = " << (effects_on[0] ? "on" : "off") << std::endl;
        effects << "reflections = " << (effects_on[1] ? "on" : "off") << std::endl;
        effects << "glow = " << (effects_on[2] ? "on" : "off") << std::endl;
    }
    {
        std::ofstream note{marker, std::ios::trunc};
        note << "First-run settings were chosen for this PC. Delete this file to choose again."
             << std::endl;
        note << fmt::format("display {}x{} at {} Hz, GPU {} ({} MB), {} cores, {} MB RAM",
                            system.display_width, system.display_height, system.refresh_hz,
                            system.gpu, system.vram_mb, system.cores, system.ram_mb)
             << std::endl;
        note << fmt::format("chosen: window {}x{} fullscreen, upscaling {}, frame cap {}, "
                            "effects {}",
                            window.first, window.second, upscale ? "on" : "off", cap, preset)
             << std::endl;
    }
    LOG_INFO(Config, "First run: window {}x{}, upscaling {}, frame cap {}, effects {}",
             window.first, window.second, upscale, cap, preset);
}

namespace {

// Seconds: fade in, hold, fade out, black pause.
constexpr float FadeIn = 1.2f;
constexpr float Hold = 5.0f;
constexpr float FadeOut = 1.2f;
constexpr float Gap = 0.8f;
constexpr float PerLine = FadeIn + Hold + FadeOut + Gap;
constexpr std::array<const char*, 2> Lines{
    "we waited, yet no one answered",
    "sometimes, we have to do things ourselves",
};

enum class IntroState { Unknown, Showing, Done };
IntroState intro_state = IntroState::Unknown;
std::chrono::steady_clock::time_point intro_start;

} // namespace

bool IntroActive() {
    return intro_state == IntroState::Showing;
}

void DrawIntro() {
    if (intro_state == IntroState::Done) {
        return;
    }
    const auto marker = UserFile("i3_intro_shown.txt");
    if (intro_state == IntroState::Unknown && std::getenv("I3_SKIP_FIRST_RUN") != nullptr) {
        intro_state = IntroState::Done;
        return;
    }
    if (intro_state == IntroState::Unknown) {
        std::error_code ec;
        if (std::filesystem::exists(marker, ec) && std::getenv("I3_FORCE_INTRO") == nullptr) {
            intro_state = IntroState::Done;
            return;
        }
        // The overlay draws from the moment the window exists, long before the game does:
        // wait for the game's first frame, then hold the game there until the lines have played.
        if (g_first_flip_ms.load(std::memory_order_relaxed) == 0) {
            return;
        }
        intro_state = IntroState::Showing;
        intro_start = std::chrono::steady_clock::now();
        DebugState.PauseGuestThreads();
    }
    const float t =
        std::chrono::duration<float>(std::chrono::steady_clock::now() - intro_start).count();
    const ImVec2 display = ImGui::GetIO().DisplaySize;
    auto* draw = ImGui::GetForegroundDrawList();
    draw->AddRectFilled({0.0f, 0.0f}, display, IM_COL32(0, 0, 0, 255));
    const int line = static_cast<int>(t / PerLine);
    if (line >= static_cast<int>(Lines.size())) {
        intro_state = IntroState::Done;
        std::ofstream{marker, std::ios::trunc} << "shown" << std::endl;
        DebugState.ResumeGuestThreads();
        return;
    }
    const float local = t - line * PerLine;
    float alpha = 0.0f;
    if (local < FadeIn) {
        alpha = local / FadeIn;
    } else if (local < FadeIn + Hold) {
        alpha = 1.0f;
    } else if (local < FadeIn + Hold + FadeOut) {
        alpha = 1.0f - (local - FadeIn - Hold) / FadeOut;
    }
    // Smooth ends.
    alpha = alpha * alpha * (3.0f - 2.0f * alpha);
    ImFont* font = Menu::Font();
    const float size = 54.0f * display.y / 1080.0f;
    const ImVec2 extent = font->CalcTextSizeA(size, FLT_MAX, 0.0f, Lines[line]);
    draw->AddText(font, size, {(display.x - extent.x) * 0.5f, (display.y - extent.y) * 0.5f},
                  IM_COL32(236, 236, 236, static_cast<int>(255.0f * alpha)), Lines[line]);
}

} // namespace I3::FirstRun
