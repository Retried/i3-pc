p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_rasterizer.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)
rep('''    if (g_pass_stat_on) {
        // Test aid: draws per render-target combination''', '''    if (g_pass_stat_on && regs.depth_buffer.DepthAddress() == g_shadow_maps.sun) {
        // Test aid: sizes of the draws into the sun's shadow map.
        const u64 n = u64(regs.num_indices) * regs.num_instances.NumInstances();
        ++g_shadow_maps.sizes[n < 100 ? 0 : n < 300 ? 1 : n < 1000 ? 2 : n < 3000 ? 3 : n < 10000 ? 4 : 5];
    }
    if (g_pass_stat_on) {
        // Test aid: draws per render-target combination''')
rep('''    u32 clears = 0;
''', '''    u32 clears = 0;
    u32 sizes[6]{};
''')
rep('''            g_shadow_maps.clears = 0;
''', '''            g_shadow_maps.clears = 0;
            if (g_pass_stat_on) {
                LOG_ERROR(Render, "sunsizes/3s: <100 {} <300 {} <1000 {} <3000 {} <10000 {} more {}",
                          g_shadow_maps.sizes[0], g_shadow_maps.sizes[1], g_shadow_maps.sizes[2],
                          g_shadow_maps.sizes[3], g_shadow_maps.sizes[4], g_shadow_maps.sizes[5]);
                std::memset(g_shadow_maps.sizes, 0, sizeof(g_shadow_maps.sizes));
            }
''')
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
