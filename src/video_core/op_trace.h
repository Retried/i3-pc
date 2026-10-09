// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <array>
#include <string>
#include <fmt/format.h>
#include "common/logging/log.h"
#include "common/types.h"

namespace VideoCore::OpTrace {

/// Ring of the last GPU operations recorded by the rasterizer (GPU thread only), written to the
/// log when the device is lost so the command that hung the GPU can be narrowed down.
struct Entry {
    char kind; ///< D draw, I indirect draw, C dispatch, X indirect dispatch
    u64 a, b, c, d;
};
inline std::array<Entry, 256> ring{};
inline u64 count = 0;

inline void Add(char kind, u64 a = 0, u64 b = 0, u64 c = 0, u64 d = 0) {
    ring[count++ % ring.size()] = {kind, a, b, c, d};
}

inline void Dump() {
    const u64 n = count < ring.size() ? count : ring.size();
    std::string text;
    for (u64 i = count - n; i < count; ++i) {
        const Entry& e = ring[i % ring.size()];
        text += fmt::format("{}:{:x},{:x},{:x},{:x} ", e.kind, e.a, e.b, e.c, e.d);
    }
    LOG_CRITICAL(Render_Vulkan, "last {} of {} GPU ops: {}", n, count, text);
}

} // namespace VideoCore::OpTrace
