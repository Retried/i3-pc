// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

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

} // namespace Common
