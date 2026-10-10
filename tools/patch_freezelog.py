"""One-off source patch: per-freeze accounting (what happened during a frame gap over 80 ms)."""
R = 'D:/i3-pc/runtime/src/'
def rw(path, pairs, head=None):
    p = R + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:60], s.count(a)); s = s.replace(a, b, 1)
    if head and head not in s:
        i = s.index('#include'); s = s[:i] + head + '\n' + s[i:]
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))

rw('common/recording.h', [('/// Time the GPU command thread', '''/// Game file reads, for the freeze log: time spent in them (microseconds) and bytes read.
inline std::atomic<unsigned long long> g_file_read_us{0}, g_file_read_bytes{0};
/// GPU command thread work the freeze log accounts for (microseconds): [0] creating images,
/// [1] uploading image data, [2] compiling pipelines, [3] whole draws, [4] whole dispatches.
inline std::atomic<unsigned long long> g_freeze_us[5]{};

/// Time the GPU command thread''')])

T = '''    const auto read_start = std::chrono::steady_clock::now();
    const s64 read_result = %s;
    Common::g_file_read_us += std::chrono::duration_cast<std::chrono::microseconds>(
                                  std::chrono::steady_clock::now() - read_start)
                                  .count();
    if (read_result > 0) {
        Common::g_file_read_bytes += read_result;
    }
    return read_result;
'''
rw('core/libraries/kernel/file_system.cpp', [
    ('''s64 PS4_SYSV_ABI sceKernelRead(s32 fd, void* buf, u64 nbytes) {
    s64 result = read(fd, buf, nbytes);''', '''s64 PS4_SYSV_ABI sceKernelRead(s32 fd, void* buf, u64 nbytes) {
    const auto read_start = std::chrono::steady_clock::now();
    s64 result = read(fd, buf, nbytes);
    Common::g_file_read_us += std::chrono::duration_cast<std::chrono::microseconds>(
                                  std::chrono::steady_clock::now() - read_start)
                                  .count();
    if (result > 0) {
        Common::g_file_read_bytes += result;
    }'''),
    ('''s64 PS4_SYSV_ABI sceKernelPread(s32 fd, void* buf, u64 nbytes, s64 offset) {
    OrbisKernelIovec iovec{buf, nbytes};
    return sceKernelPreadv(fd, &iovec, 1, offset);
}''', '''s64 PS4_SYSV_ABI sceKernelPread(s32 fd, void* buf, u64 nbytes, s64 offset) {
    OrbisKernelIovec iovec{buf, nbytes};
''' + T % 'sceKernelPreadv(fd, &iovec, 1, offset)' + '}'),
], head='#include <chrono>\n#include "common/recording.h"')

rw('video_core/renderer_vulkan/vk_rasterizer.cpp', [
    ('''void Rasterizer::OnSubmit() {
    g_shadow_maps.NextFrame();
''', '''void Rasterizer::OnSubmit() {
    g_shadow_maps.NextFrame();
    {
        // Freeze log: when a frame took over 80 ms, say where the time went. Thread CPU time
        // far below the gap means this thread waited (for the game or the GPU).
        static auto last = std::chrono::steady_clock::now();
        static u64 last_cpu = 0, last_read_us = 0, last_read_bytes = 0, last_wait = 0;
        static u64 last_part[5]{};
        FILETIME creation, exit, kernel, user;
        GetThreadTimes(GetCurrentThread(), &creation, &exit, &kernel, &user);
        const auto ticks = [](const FILETIME& t) {
            return (u64(t.dwHighDateTime) << 32) | t.dwLowDateTime;
        };
        const u64 cpu = (ticks(kernel) + ticks(user)) / 10;
        const u64 read_us = Common::g_file_read_us.load();
        const u64 read_bytes = Common::g_file_read_bytes.load();
        const u64 wait = Common::g_wait_total_us.load();
        const auto now = std::chrono::steady_clock::now();
        const u64 gap_us = std::chrono::duration_cast<std::chrono::microseconds>(now - last).count();
        u64 part[5];
        for (int i = 0; i < 5; ++i) {
            part[i] = Common::g_freeze_us[i].load();
        }
        if (gap_us > 80'000) {
            LOG_ERROR(Render, "freeze {} ms: render thread cpu {} ms (gpu waits {}, image create {}, "
                              "image upload {}, pipeline compile {}, draws {}, dispatches {}); "
                              "game file reads {} ms, {} KB",
                      gap_us / 1000, (cpu - last_cpu) / 1000, (wait - last_wait) / 1000,
                      (part[0] - last_part[0]) / 1000, (part[1] - last_part[1]) / 1000,
                      (part[2] - last_part[2]) / 1000, (part[3] - last_part[3]) / 1000,
                      (part[4] - last_part[4]) / 1000, (read_us - last_read_us) / 1000,
                      (read_bytes - last_read_bytes) / 1024);
        }
        last = now;
        last_cpu = cpu;
        last_read_us = read_us;
        last_read_bytes = read_bytes;
        last_wait = wait;
        std::ranges::copy(part, last_part);
    }
'''),
])
rw('common/recording.h', [('inline std::atomic<unsigned long long> g_wait_us[3]{};',
   'inline std::atomic<unsigned long long> g_wait_us[3]{};\n/// The same, never reset (freeze log).\ninline std::atomic<unsigned long long> g_wait_total_us{0};')])
rw('video_core/renderer_vulkan/vk_scheduler.cpp', [('''    Common::g_wait_us[2] += std::chrono::duration_cast<std::chrono::microseconds>(
                                std::chrono::steady_clock::now() - wait_start)
                                .count();''', '''    const u64 waited_us = std::chrono::duration_cast<std::chrono::microseconds>(
                              std::chrono::steady_clock::now() - wait_start)
                              .count();
    Common::g_wait_us[2] += waited_us;
    Common::g_wait_total_us += waited_us;''')])
print('patched')
