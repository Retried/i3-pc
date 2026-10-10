"""One-off source patch: per-render-target draw histogram (test aid, I3_PASSSTAT=1)."""
p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_rasterizer.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)


rep('''    VideoCore::OpTrace::Add('D', pipeline->GetStage(Shader::SwStage::Vertex).pgm_hash,
''', '''    if (g_pass_stat_on) {
        // Test aid: draws per render-target combination, logged with the other statistics.
        const bool color = pipeline->GetStage(Shader::SwStage::Fragment).mrt_mask != 0;
        const auto& cb = regs.color_buffers[0];
        const u64 color_addr = color ? cb.Address() : 0;
        const u64 depth_addr = regs.depth_buffer.DepthValid() ? regs.depth_buffer.DepthAddress() : 0;
        auto it = std::ranges::find_if(g_pass_stat, [&](const PassStat& e) {
            return e.color == color_addr && e.depth == depth_addr;
        });
        if (it == g_pass_stat.end()) {
            g_pass_stat.push_back({color_addr, depth_addr, color ? cb.Pitch() : 0,
                                   color ? cb.Height() : 0, regs.depth_buffer.Pitch(),
                                   regs.depth_buffer.Height(), 0, 0});
            it = std::prev(g_pass_stat.end());
        }
        ++it->draws;
        it->indices += u64(regs.num_indices) * regs.num_instances.NumInstances();
    }
    VideoCore::OpTrace::Add('D', pipeline->GetStage(Shader::SwStage::Vertex).pgm_hash,
''')
rep('''            last_thread = thread_ms;
''', '''            if (g_pass_stat_on) {
                std::ranges::sort(g_pass_stat, std::greater{}, &PassStat::draws);
                for (size_t i = 0; i < std::min<size_t>(g_pass_stat.size(), 24); ++i) {
                    const auto& e = g_pass_stat[i];
                    LOG_ERROR(Render, "pass/3s: draws {} indices {} color {:#x} {}x{} depth {:#x} {}x{}",
                              e.draws, e.indices, e.color, e.cw, e.ch, e.depth, e.dw, e.dh);
                }
                g_pass_stat.clear();
            }
            last_thread = thread_ms;
''')
i = s.index('namespace Vulkan {') + len('namespace Vulkan {\n')
s = s[:i] + '''
struct PassStat {
    u64 color, depth;
    u32 cw, ch, dw, dh;
    u32 draws;
    u64 indices;
};
static std::vector<PassStat> g_pass_stat;
static const bool g_pass_stat_on = std::getenv("I3_PASSSTAT") != nullptr;
''' + s[i:]
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
