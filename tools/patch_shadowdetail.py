"""One-off source patch: Shadow Detail option (small objects cast no sun shadow)."""
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


rw('common/recording.h', [('inline std::atomic<int> g_shadow_rate[2]{};', '''inline std::atomic<int> g_shadow_rate[2]{};

/// Draws with fewer indices than this are left out of the sun's shadow map (0 = none are).
inline std::atomic<unsigned> g_shadow_min_indices{0};''')])

rw('video_core/renderer_vulkan/vk_rasterizer.cpp', [
    ('bool Skip(const AmdGpu::DepthBuffer& depth, bool clear) {',
     'bool Skip(const AmdGpu::DepthBuffer& depth, bool clear, u64 indices) {'),
    ('g_shadow_maps.Skip(regs.depth_buffer, regs.depth_render_control.depth_clear_enable)',
     '''g_shadow_maps.Skip(regs.depth_buffer, regs.depth_render_control.depth_clear_enable,
                           u64(regs.num_indices) * regs.num_instances.NumInstances())'''),
    ('''        const bool skip = rate == 2 ? !clear : (rate == 1 && ((frame + kind) & 1) != 0);''',
     '''        bool skip = rate == 2 ? !clear : (rate == 1 && ((frame + kind) & 1) != 0);
        // Shadow Detail: small objects are left out of the sun's map (never the clear).
        skip |= kind == 0 && !clear &&
                indices < Common::g_shadow_min_indices.load(std::memory_order_relaxed);'''),
])

rw('core/i3/menu.cpp', [
    ('''constexpr std::array<const char*, 3> ShadowRateNames{"Every Frame", "Every 2nd Frame", "Off"};
''', '''constexpr std::array<const char*, 3> ShadowRateNames{"Every Frame", "Every 2nd Frame", "Off"};
// Shadow Detail: objects with fewer indices than this cast no sun shadow.
int shadow_detail = 0;
constexpr std::array<const char*, 3> ShadowDetailKeys{"full", "reduced", "low"};
constexpr std::array<const char*, 3> ShadowDetailNames{"Full", "Reduced", "Low"};
constexpr std::array<u32, 3> ShadowDetailIndices{0, 300, 1000};
'''),
    ('''        Common::g_shadow_rate[kind] = shadow_rate[kind];
    }''', '''        Common::g_shadow_rate[kind] = shadow_rate[kind];
    }
    Common::g_shadow_min_indices = ShadowDetailIndices[shadow_detail];'''),
    ('''        file << ShadowKeys[kind] << " = " << ShadowRateKeys[shadow_rate[kind]] << "''' + BS + '''n";
    }''', '''        file << ShadowKeys[kind] << " = " << ShadowRateKeys[shadow_rate[kind]] << "''' + BS + '''n";
    }
    file << "shadow_detail = " << ShadowDetailKeys[shadow_detail] << "''' + BS + '''n";'''),
    ('''        for (size_t kind = 0; kind < shadow_rate.size(); kind++) {
            if (name == ShadowKeys[kind]) {''', '''        if (name == "shadow_detail") {
            shadow_detail = value == ShadowDetailKeys[2] ? 2 : value == ShadowDetailKeys[1];
        }
        for (size_t kind = 0; kind < shadow_rate.size(); kind++) {
            if (name == ShadowKeys[kind]) {'''),
    ('''        rows.push_back({"BACK", "", "Return to the previous menu"});
    }
    return rows;''', '''        rows.push_back({"Shadow Detail", ShadowDetailNames[shadow_detail],
                        "Reduced and Low leave small objects out of the sun's shadows. Applies at once",
                        true});
        rows.push_back({"BACK", "", "Return to the previous menu"});
    }
    return rows;'''),
    ('''            shadow_rate[kind] = (shadow_rate[kind] + step + 3) % 3;
            ApplyEffects();
            SaveEffects();
        }''', '''            shadow_rate[kind] = (shadow_rate[kind] + step + 3) % 3;
            ApplyEffects();
            SaveEffects();
        } else if (kind == static_cast<int>(shadow_rate.size())) {
            shadow_detail = (shadow_detail + step + 3) % 3;
            ApplyEffects();
            SaveEffects();
        }'''),
])
print('patched')
