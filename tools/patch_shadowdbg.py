p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_rasterizer.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)
rep('''        const int rate = Common::g_shadow_rate[kind].load(std::memory_order_relaxed);
        // The two kinds take turns, which keeps the cost of consecutive frames even.
        return rate == 2 || (rate == 1 && ((frame + kind) & 1) != 0);''',
'''        const int rate = Common::g_shadow_rate[kind].load(std::memory_order_relaxed);
        // The two kinds take turns, which keeps the cost of consecutive frames even.
        const bool skip = rate == 2 || (rate == 1 && ((frame + kind) & 1) != 0);
        ++seen[kind][skip];
        clears += clear;
        return skip;''')
rep('''    bool Skip(const AmdGpu::DepthBuffer& depth) {''', '''    u32 seen[2][2]{};
    u32 clears = 0;
    u64 logged_frame = 0;
    bool Skip(const AmdGpu::DepthBuffer& depth, bool clear) {''')
rep('g_shadow_maps.Skip(regs.depth_buffer)', 'g_shadow_maps.Skip(regs.depth_buffer, regs.depth_render_control.depth_clear_enable)')
rep('''            if (g_pass_stat_on) {
                std::ranges::sort''', '''            LOG_ERROR(Render, "shadow/3s: frames {} sun drawn {} skipped {} local drawn {} skipped {} clears {}",
                      g_shadow_maps.frame - g_shadow_maps.logged_frame, g_shadow_maps.seen[0][0],
                      g_shadow_maps.seen[0][1], g_shadow_maps.seen[1][0], g_shadow_maps.seen[1][1],
                      g_shadow_maps.clears);
            g_shadow_maps.logged_frame = g_shadow_maps.frame;
            std::memset(g_shadow_maps.seen, 0, sizeof(g_shadow_maps.seen));
            g_shadow_maps.clears = 0;
            if (g_pass_stat_on) {
                std::ranges::sort''')
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
