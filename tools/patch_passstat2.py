"""One-off source patch: pass histogram keyed by viewport too."""
p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_rasterizer.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)


rep('''            return e.color == color_addr && e.depth == depth_addr;
''', '''            return e.color == color_addr && e.depth == depth_addr && e.vx == vx && e.vy == vy &&
                   e.vw == vw;
''')
rep('''        auto it = std::ranges::find_if(g_pass_stat, [&](const PassStat& e) {''',
    '''        const auto& vp = regs.viewports[0];
        const int vw = int(vp.xscale * 2), vx = int(vp.xoffset - vp.xscale),
                  vy = int(vp.yoffset - std::abs(vp.yscale));
        auto it = std::ranges::find_if(g_pass_stat, [&](const PassStat& e) {''')
rep('''                                   regs.depth_buffer.Height(), 0, 0});''',
    '''                                   regs.depth_buffer.Height(), 0, 0, vx, vy, vw});''')
rep('''    u64 indices;
};''', '''    u64 indices;
    int vx, vy, vw;
};''')
rep('''color {:#x} {}x{} depth {:#x} {}x{}",
                              e.draws, e.indices, e.color, e.cw, e.ch, e.depth, e.dw, e.dh);''',
    '''color {:#x} {}x{} depth {:#x} {}x{} vp {},{} w{}",
                              e.draws, e.indices, e.color, e.cw, e.ch, e.depth, e.dw, e.dh, e.vx,
                              e.vy, e.vw);''')
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
