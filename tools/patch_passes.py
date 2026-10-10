"""One-off source patch: skippable render passes (by fragment shader hash) and a pass lister."""
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


open(ROOT + 'src/video_core/pass_filter.h', 'w', encoding='utf-8', newline='\n').write('''// SPDX-License-Identifier: GPL-2.0-or-later

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
''')

rw('src/video_core/renderer_vulkan/vk_rasterizer.cpp', [
    ('''    if (DrawHasNoEffect(pipeline, regs)) {
        ++g_stats.filtered;
        return;
    }
''', '''    if (DrawHasNoEffect(pipeline, regs)) {
        ++g_stats.filtered;
        return;
    }
    {
        const u64 fs_hash = pipeline->GetStage(Shader::SwStage::Fragment).pgm_hash;
        if (VideoCore::PassFilter::skipped_count.load(std::memory_order_relaxed) != 0 &&
            VideoCore::PassFilter::IsSkipped(fs_hash)) {
            ++g_stats.filtered;
            return;
        }
        // Test aid: script action "listfs" collects the fullscreen passes (3 or 4 vertices)
        // for a while and writes them, in first-use order, to fs_list.txt.
        if (VideoCore::PassFilter::listing_frames.load(std::memory_order_relaxed) > 0 &&
            regs.num_indices <= 4) {
            static std::vector<std::pair<u64, u32>> seen;
            auto it = std::ranges::find(seen, fs_hash, &std::pair<u64, u32>::first);
            if (it == seen.end()) {
                seen.emplace_back(fs_hash, 1);
            } else {
                ++it->second;
            }
            if (VideoCore::PassFilter::listing_frames.fetch_sub(1) == 1) {
                if (std::FILE* file = std::fopen("fs_list.txt", "w")) {
                    for (const auto& [hash, count] : seen) {
                        std::fprintf(file, "%llx %u\\n", static_cast<unsigned long long>(hash),
                                     count);
                    }
                    std::fclose(file);
                }
                seen.clear();
            }
        }
    }
'''),
], includes=('#include "video_core/pass_filter.h"',))

rw('src/sdl_window.cpp', [
    ('        } else if (action == "rec=on" || action == "rec=off") {',
     '''        } else if (action.starts_with("skipfs=")) {
            // "skipfs=<hex hash>" stops draws with that fragment shader, "skipfs=clear" resumes
            // them all; "listfs" (below) names the candidates.
            const auto value = action.substr(7);
            if (value == "clear") {
                VideoCore::PassFilter::Clear();
            } else {
                VideoCore::PassFilter::Skip(std::strtoull(value.c_str(), nullptr, 16));
            }
        } else if (action == "listfs") {
            // Counts draws, not frames: about three seconds of fullscreen passes.
            VideoCore::PassFilter::listing_frames = 4000;
        } else if (action == "rec=on" || action == "rec=off") {'''),
], includes=('#include "video_core/pass_filter.h"',))
print('patched')
