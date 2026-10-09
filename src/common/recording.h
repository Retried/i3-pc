// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <atomic>

namespace Common {

/// Gameplay recording for test runs (script actions "rec=on" / "rec=off"): while set, the
/// presenter appends half-size RGB frames at 30 per second to <user dir>/capture/frames.rgb
/// and the audio output appends its float samples to <user dir>/capture/audio.f32.
inline std::atomic<bool> g_recording{false};

} // namespace Common
