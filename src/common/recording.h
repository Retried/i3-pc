// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <chrono>
#include <atomic>

namespace Common {

/// Gameplay recording for test runs (script actions "rec=on" / "rec=off"): while set, the
/// presenter appends half-size RGB frames at 30 per second to <user dir>/capture/frames.rgb
/// and the audio output appends its float samples to <user dir>/capture/audio.f32.
inline std::atomic<bool> g_recording{false};

/// Set by the PC options of a game build: present on every tick of the frame clock whatever
/// flip rate the game asked for (the game's own 30 FPS limit is such a request).
inline std::atomic<bool> g_unlock_flip_rate{false};

/// Benchmark capture (script actions "bench=on" / "bench=off"): while set, the time between
/// presented frames is appended, in milliseconds, to bench_frametimes.txt.
inline std::atomic<bool> g_bench{false};
// Test switch (script action "fastpath=on|off"): the short path for repeated draws.
inline std::atomic<bool> g_draw_fastpath{true};

/// Shadow map updates of the inFAMOUS Second Son build, set by its PC options: 0 every frame,
/// 1 every second frame (the map of the frame before is reused in between), 2 never (no
/// shadows of that kind). [0] the sun's map, [1] the maps of local lights.
inline std::atomic<int> g_shadow_rate[2]{};

/// Draws with fewer indices than this are left out of the sun's shadow map (0 = none are).
inline std::atomic<unsigned> g_shadow_min_indices{0};

/// Number of save data mounts the game has made since it started. inFAMOUS Second Son mounts
/// a save when a game is continued, loaded or first saved, so 0 means its title menu is up.
inline std::atomic<int> g_save_mounts{0};

/// Game file reads, for the freeze log: time spent in them (microseconds) and bytes read.
inline std::atomic<unsigned long long> g_file_read_us{0}, g_file_read_bytes{0};
/// GPU command thread work the freeze log accounts for (microseconds): [0] creating images,
/// [1] uploading image data, [2] compiling pipelines, [3] whole draws, [4] whole dispatches,
/// [5] obtaining buffers, [6] compiling shader modules, [7] making buffer memory resident,
/// [8] uploading buffer data.
inline std::atomic<unsigned long long> g_freeze_us[9]{};

/// Time the GPU command thread spent blocked on the GPU, in microseconds, by reason
/// (0 upload stream wrapped, 1 fault buffer, 2 every wait). Logged with the thread CPU time.
inline std::atomic<unsigned long long> g_wait_us[3]{};
/// The same, never reset (freeze log).
inline std::atomic<unsigned long long> g_wait_total_us{0};

/// Set from the environment variable I3_FREEZELOG: the freeze log and its timers are on.
/// Off by default: the timers sit in paths that run tens of thousands of times per frame
/// and halved the frame rate when they were always on.
inline bool g_freeze_log = false;
/// Bytes of buffer data uploaded from guest memory (freeze log).
inline std::atomic<unsigned long long> g_upload_bytes{0};

/// Adds the time it lives to one of the g_freeze_us counters.
struct FreezeTimer {
    int slot;
    std::chrono::steady_clock::time_point start;
    explicit FreezeTimer(int slot_) : slot{slot_} {
        if (g_freeze_log) {
            start = std::chrono::steady_clock::now();
        }
    }
    ~FreezeTimer() {
        if (g_freeze_log) {
            g_freeze_us[slot] += std::chrono::duration_cast<std::chrono::microseconds>(
                                     std::chrono::steady_clock::now() - start)
                                     .count();
        }
    }
};

} // namespace Common
