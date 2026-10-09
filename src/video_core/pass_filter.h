// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <array>
#include <atomic>
#include "common/types.h"

// Render passes switched off at the runtime layer: draws whose fragment shader hash is listed
// are not issued. Used for the per-effect graphics options of games whose engine has no
// switch of its own, and by test scripts to find out which shader belongs to which effect.
namespace VideoCore::PassFilter {

inline std::array<std::atomic<u64>, 32> skipped{};
inline std::atomic<u32> skipped_count{0};
/// Frames left in which the fragment shaders of small (fullscreen) draws are collected.
inline std::atomic<int> listing_frames{0};

inline bool IsSkipped(u64 fs_hash) {
    const u32 count = skipped_count.load(std::memory_order_relaxed);
    for (u32 i = 0; i < count; ++i) {
        if (skipped[i].load(std::memory_order_relaxed) == fs_hash) {
            return true;
        }
    }
    return false;
}

inline void Skip(u64 fs_hash) {
    if (IsSkipped(fs_hash)) {
        return;
    }
    const u32 count = skipped_count.load();
    if (count < skipped.size()) {
        skipped[count] = fs_hash;
        skipped_count = count + 1;
    }
}

inline void Clear() {
    skipped_count = 0;
}

} // namespace VideoCore::PassFilter
