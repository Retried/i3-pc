"""One-off source patch: test switch I3_SKIPDEPTH=<hex depth address>[,..] drops draws into those depth targets."""
p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_rasterizer.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:60], s.count(a))
    s = s.replace(a, b, 1)


rep('''    const auto& regs = liverpool->regs;
    const GraphicsPipeline* pipeline = pipeline_cache.GetGraphicsPipeline();
    if (!pipeline) {
        ++g_stats.no_pipeline;
        return;
    }
    if (DrawHasNoEffect(pipeline, regs)) {''', '''    const auto& regs = liverpool->regs;
    if (!g_skip_depth.empty() &&
        std::ranges::find(g_skip_depth, regs.depth_buffer.DepthAddress()) != g_skip_depth.end()) {
        ++g_stats.filtered;
        return;
    }
    const GraphicsPipeline* pipeline = pipeline_cache.GetGraphicsPipeline();
    if (!pipeline) {
        ++g_stats.no_pipeline;
        return;
    }
    if (DrawHasNoEffect(pipeline, regs)) {''')
rep('''static std::vector<PassStat> g_pass_stat;
''', '''static std::vector<PassStat> g_pass_stat;
static const std::vector<u64> g_skip_depth = [] {
    std::vector<u64> list;
    if (const char* env = std::getenv("I3_SKIPDEPTH")) {
        char* end = nullptr;
        for (const char* at = env; *at; at = *end ? end + 1 : end) {
            list.push_back(std::strtoull(at, &end, 16));
        }
    }
    return list;
}();
''')
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
