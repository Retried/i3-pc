"""One-off source patch: wait accounting for the render thread (test aid)."""
R = 'D:/i3-pc/runtime/src/'


def rw(path, pairs):
    p = R + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:60], s.count(a))
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('common/recording.h', [('} // namespace Common', '''/// Time the GPU command thread spent blocked on the GPU, in microseconds, by reason
/// (0 upload stream wrapped, 1 fault buffer, 2 every wait). Logged with the thread CPU time.
inline std::atomic<unsigned long long> g_wait_us[3]{};

} // namespace Common''')])

T = '''        const auto wait_start = std::chrono::steady_clock::now();
        scheduler.Wait(%s);
        Common::g_wait_us[%d] += std::chrono::duration_cast<std::chrono::microseconds>(
                                    std::chrono::steady_clock::now() - wait_start)
                                    .count();
'''
rw('video_core/buffer_cache/buffer.cpp', [
    ('        scheduler.Wait(watch.tick);\n', T % ('watch.tick', 0)),
    ('#include "', '#include <chrono>\n#include "common/recording.h"\n#include "'),
][:1])
rw('video_core/buffer_cache/fault_manager.cpp', [
    ('        scheduler.Wait(wait_tick);\n', T % ('wait_tick', 1)),
])
rw('video_core/renderer_vulkan/vk_scheduler.cpp', [
    ('    work_semaphore.Wait(tick);\n}', '''    const auto wait_start = std::chrono::steady_clock::now();
    work_semaphore.Wait(tick);
    Common::g_wait_us[2] += std::chrono::duration_cast<std::chrono::microseconds>(
                                std::chrono::steady_clock::now() - wait_start)
                                .count();
}'''),
])
rw('video_core/renderer_vulkan/vk_rasterizer.cpp', [
    ('''            last_thread = thread_ms;
''', '''            LOG_ERROR(Render, "wait/3s ms: stream {} fault {} all {}",
                      Common::g_wait_us[0].exchange(0) / 1000,
                      Common::g_wait_us[1].exchange(0) / 1000,
                      Common::g_wait_us[2].exchange(0) / 1000);
            last_thread = thread_ms;
'''),
])
for f in ('video_core/buffer_cache/buffer.cpp', 'video_core/buffer_cache/fault_manager.cpp',
          'video_core/renderer_vulkan/vk_scheduler.cpp', 'video_core/renderer_vulkan/vk_rasterizer.cpp'):
    p = R + f
    s = open(p, encoding='utf-8', newline='').read()
    if 'common/recording.h' not in s:
        i = s.index('#include')
        s = s[:i] + '#include <chrono>\n#include "common/recording.h"\n' + s[i:]
        open(p, 'w', encoding='utf-8', newline='').write(s)
print('patched')
