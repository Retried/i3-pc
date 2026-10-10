"""One-off source patch: non-blocking mirror uses its own download buffer."""
R = 'D:/i3-pc/runtime/src/video_core/buffer_cache/'


def load(p):
    s = open(R + p, encoding='utf-8', newline='').read()
    return s.replace('\r\n', '\n'), ('\r\n' if '\r\n' in s else '\n')


def save(p, s, nl):
    open(R + p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


s, nl = load('buffer_cache.cpp')
a = s.index('void BufferCache::MirrorToGuest(')
b = s.index('// Debug aid: bytes of the GPU-side copy')
s = s[:a] + '''void BufferCache::MirrorToGuest(std::span<const std::pair<VAddr, u32>> ranges) {
    if (ranges.empty()) {
        return;
    }
    u64 total = 0;
    for (const auto& [addr, size] : ranges) {
        total += Common::AlignUp(size, 64);
    }
    // inFAMOUS Second Son does not block on the GPU here: the copy is submitted and written to
    // guest memory when the GPU has reached it, normally early in the next frame. What its CPU
    // side needs from these results (an exposure-like block, once per frame) tolerates that,
    // and the blocking wait cost 1.5 to 2 ms of every frame. I3_SYNC_MIRROR=1 waits again.
    // The copies land in a buffer of their own: a staging allocation can be recycled before a
    // deferred read gets to it (seen as a crash after a checkpoint reload stalled the frame).
    static const bool async = Common::ElfInfo::Instance().GameSerial() == "CUSA00004" &&
                              std::getenv("I3_SYNC_MIRROR") == nullptr;
    if (async && total <= MIRROR_BUFFER_SIZE / 8 && mirrors_in_flight < 6) {
        if (!mirror_buffer) {
            mirror_buffer = std::make_unique<Buffer>(instance, 0, MIRROR_BUFFER_SIZE,
                                                     MemoryType::HostCached, "Mirror Buffer");
        }
        if (mirror_offset + total > MIRROR_BUFFER_SIZE) {
            mirror_offset = 0;
        }
        const u64 base = mirror_offset;
        mirror_offset += total;
        u64 cursor = 0;
        for (const auto& [addr, size] : ranges) {
            const auto [buffer, offset] = ObtainBuffer(addr, size, false);
            const vk::BufferCopy copy{offset, base + cursor, size};
            runtime.CopyBuffer(buffer, mirror_buffer.get(), std::span{&copy, 1});
            cursor += Common::AlignUp(size, 64);
        }
        const u64 batch = ++mirror_batch;
        ++mirrors_in_flight;
        scheduler.DeferOperation(
            [this, base, total, batch, list = std::vector(ranges.begin(), ranges.end())] {
                mirror_buffer->Invalidate(base, total);
                const u8* data = mirror_buffer->mapped_data.data() + base;
                for (const auto& [addr, size] : list) {
                    // The game may have unmapped the range in the meantime (level reload).
                    if (memory->IsValidMapping(addr, size)) {
                        memory->TryWriteBacking(std::bit_cast<u8*>(addr), data, size);
                    }
                    data += Common::AlignUp(size, 64);
                }
                --mirrors_in_flight;
                // Ranges stay protected from re-upload until the newest batch has landed.
                if (batch == mirror_batch) {
                    pending_mirror_ranges.Clear();
                }
            });
        scheduler.Flush();
        return;
    }
    const auto download = staging_pool.Request(total, VideoCore::MemoryType::HostCached);
    u64 cursor = 0;
    for (const auto& [addr, size] : ranges) {
        const auto [buffer, offset] = ObtainBuffer(addr, size, false);
        const vk::BufferCopy copy{offset, download.offset + cursor, size};
        runtime.CopyBuffer(buffer, download.buffer, std::span{&copy, 1});
        cursor += Common::AlignUp(size, 64);
    }
    scheduler.Finish();
    // Deferred batches that were still on their way have landed with this wait; run them
    // first so that this newer data is what stays in guest memory.
    scheduler.PopPendingOperations();
    download.buffer->Invalidate(download.offset, total);
    cursor = 0;
    for (const auto& [addr, size] : ranges) {
        memory->TryWriteBacking(std::bit_cast<u8*>(addr), download.mapped + cursor, size);
        cursor += Common::AlignUp(size, 64);
    }
    pending_mirror_ranges.Clear();
}

''' + s[b:]
save('buffer_cache.cpp', s, nl)

s, nl = load('buffer_cache.h')
a = '    u64 mirror_batch = 0;'
assert s.count(a) == 1
s = s.replace(a, '''    u64 mirror_batch = 0;
    /// Download target of the non-blocking mirror, used as a ring.
    static constexpr u64 MIRROR_BUFFER_SIZE = 32ULL << 20;
    std::unique_ptr<Buffer> mirror_buffer;
    u64 mirror_offset = 0;
    u32 mirrors_in_flight = 0;''')
save('buffer_cache.h', s, nl)
print('patched')
