"""One-off source patch: shadow map update options (Sun Shadows, Light Shadows)."""
R = 'D:/i3-pc/runtime/src/'
BS = chr(92)


def rw(path, pairs):
    p = R + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:60], s.count(a))
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('common/recording.h', [('/// Time the GPU command thread', '''/// Shadow map updates of the inFAMOUS Second Son build, set by its PC options: 0 every frame,
/// 1 every second frame (the map of the frame before is reused in between), 2 never (no
/// shadows of that kind). [0] the sun's map, [1] the maps of local lights.
inline std::atomic<int> g_shadow_rate[2]{};

/// Time the GPU command thread''')])

rw('video_core/renderer_vulkan/vk_rasterizer.cpp', [
    ('''    const auto& regs = liverpool->regs;
    if (!g_skip_depth.empty() &&''', '''    const auto& regs = liverpool->regs;
    if (g_shadow_maps.enabled && g_shadow_maps.Skip(regs.depth_buffer)) {
        ++g_stats.filtered;
        return;
    }
    if (!g_skip_depth.empty() &&'''),
    ('''void Rasterizer::OnSubmit() {
''', '''void Rasterizer::OnSubmit() {
    g_shadow_maps.NextFrame();
'''),
    ('''static std::vector<PassStat> g_pass_stat;
''', '''static std::vector<PassStat> g_pass_stat;

// Shadow map options of the inFAMOUS Second Son build. About 70% of the game's draws go into
// shadow maps, so how often those are redrawn is the largest single cost the player can trade.
// Shadow maps are the square depth targets: the sun's is the 2048x2048 one that received the
// most draws in the frame before (a second 2048x2048 target is left alone: dropping it changes
// neither the picture nor the cost), the 1024x1024 ones belong to local lights. A map that gets
// no draws in a frame is not cleared either, so it keeps what the frame before drew into it.
struct ShadowMaps {
    const bool enabled = Common::ElfInfo::Instance().GameSerial() == "CUSA00004";
    u64 frame = 0;
    u64 sun = 0;
    struct Count {
        u64 address;
        u32 draws;
    };
    boost::container::small_vector<Count, 4> large;

    bool Skip(const AmdGpu::DepthBuffer& depth) {
        const u32 size = depth.Pitch();
        if (size < 1024 || size != depth.Height() || !depth.DepthValid()) {
            return false;
        }
        const u64 address = depth.DepthAddress();
        int kind = 1;
        if (size >= 2048) {
            auto it = std::ranges::find(large, address, &Count::address);
            if (it == large.end()) {
                large.push_back({address, 0});
                it = std::prev(large.end());
            }
            ++it->draws;
            if (address != sun) {
                return false;
            }
            kind = 0;
        }
        const int rate = Common::g_shadow_rate[kind].load(std::memory_order_relaxed);
        // The two kinds take turns, which keeps the cost of consecutive frames even.
        return rate == 2 || (rate == 1 && ((frame + kind) & 1) != 0);
    }

    void NextFrame() {
        ++frame;
        if (!large.empty()) {
            sun = std::ranges::max_element(large, {}, &Count::draws)->address;
            large.clear();
        }
    }
};
static ShadowMaps g_shadow_maps;
'''),
])

rw('core/i3/menu.cpp', [
    ('''bool unlock_frame_rate = true;
''', '''bool unlock_frame_rate = true;
// How often the shadow maps are redrawn: [0] the sun's, [1] those of local lights.
std::array<int, 2> shadow_rate{};
constexpr std::array<const char*, 2> ShadowKeys{"sun_shadows", "light_shadows"};
constexpr std::array<const char*, 3> ShadowRateKeys{"full", "half", "off"};
constexpr std::array<const char*, 3> ShadowRateNames{"Every Frame", "Every 2nd Frame", "Off"};
'''),
    ('''    Common::g_unlock_flip_rate = unlock_frame_rate;
}''', '''    Common::g_unlock_flip_rate = unlock_frame_rate;
    for (size_t kind = 0; kind < shadow_rate.size(); kind++) {
        Common::g_shadow_rate[kind] = shadow_rate[kind];
    }
}'''),
    ('''    file << "unlock_frame_rate = " << (unlock_frame_rate ? "on" : "off") << "''' + BS + '''n";
}''', '''    file << "unlock_frame_rate = " << (unlock_frame_rate ? "on" : "off") << "''' + BS + '''n";
    for (size_t kind = 0; kind < shadow_rate.size(); kind++) {
        file << ShadowKeys[kind] << " = " << ShadowRateKeys[shadow_rate[kind]] << "''' + BS + '''n";
    }
}'''),
    ('''        if (name == "unlock_frame_rate") {
            unlock_frame_rate = value != "off";
        }''', '''        if (name == "unlock_frame_rate") {
            unlock_frame_rate = value != "off";
        }
        for (size_t kind = 0; kind < shadow_rate.size(); kind++) {
            if (name == ShadowKeys[kind]) {
                shadow_rate[kind] = IndexOf(ShadowRateKeys, std::string_view{value}, 0);
            }
        }'''),
    ('''                        true});
        rows.push_back({"BACK", "", "Return to the previous menu"});
    }
    return rows;''', '''                        true});
        rows.push_back({"Sun Shadows", ShadowRateNames[shadow_rate[0]],
                        "How often the sun's shadow map is redrawn: the largest cost of a frame. "
                        "Every 2nd Frame is faster, shadows may trail while moving. Applies at once",
                        true});
        rows.push_back({"Light Shadows", ShadowRateNames[shadow_rate[1]],
                        "The same for shadows cast by lamps and fires. Applies at once", true});
        rows.push_back({"BACK", "", "Return to the previous menu"});
    }
    return rows;'''),
    ('''        } else if (row == 8 + static_cast<int>(effects.size())) {
            unlock_frame_rate = !unlock_frame_rate;
            ApplyEffects();
            SaveEffects();
        }''', '''        } else if (row == 8 + static_cast<int>(effects.size())) {
            unlock_frame_rate = !unlock_frame_rate;
            ApplyEffects();
            SaveEffects();
        } else if (const int kind = row - 9 - static_cast<int>(effects.size());
                   kind >= 0 && kind < static_cast<int>(shadow_rate.size())) {
            shadow_rate[kind] = (shadow_rate[kind] + step + 3) % 3;
            ApplyEffects();
            SaveEffects();
        }'''),
])
print('patched')
