// SPDX-FileCopyrightText: Copyright 2024 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <chrono>
#include "common/recording.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <thread>
#include <magic_enum/magic_enum.hpp>

#include <cstdlib>
#include <cstring>
#include <unordered_map>
#include <vector>
#include <unordered_set>
#include <xxhash.h>
#include "common/elf_info.h"
#include "common/alignment.h"
#include "core/debug_state.h"
#include "core/memory.h"
#include "video_core/amdgpu/liverpool.h"
#include "video_core/buffer_cache/buffer.h"
#include "video_core/buffer_cache/buffer_cache.h"
#include "video_core/buffer_cache/memory_tracker.h"
#include "video_core/buffer_cache/region_definitions.h"
#include "video_core/renderer_vulkan/vk_graphics_pipeline.h"
#include "video_core/renderer_vulkan/vk_instance.h"
#include "video_core/renderer_vulkan/vk_runtime.h"
#include "video_core/renderer_vulkan/vk_scheduler.h"
#include "video_core/texture_cache/texture_cache.h"

#include <vk_mem_alloc.h>

namespace VideoCore {

// Counts the events after which guest memory read by an earlier draw may hold something
// else: every command that is not a draw, a register write or padding, every compute
// queue command, every submitted command buffer and every copy back of compute results.
u64 g_stream_epoch = 0;
static u64 mirror_words_kept = 0;

static constexpr size_t GDS_BUFFER_SIZE = 64_KB;
static constexpr size_t STREAM_BUFFER_SIZE = 128_MB;

static constexpr auto ARENA_USAGE =
    vk::BufferUsageFlagBits::eTransferSrc | vk::BufferUsageFlagBits::eTransferDst |
    vk::BufferUsageFlagBits::eUniformBuffer | vk::BufferUsageFlagBits::eStorageBuffer |
    vk::BufferUsageFlagBits::eIndexBuffer | vk::BufferUsageFlagBits::eVertexBuffer |
    vk::BufferUsageFlagBits::eIndirectBuffer | vk::BufferUsageFlagBits::eShaderDeviceAddress;

std::optional<u32> FindMemoryType(const vk::PhysicalDeviceMemoryProperties& properties,
                                  vk::MemoryPropertyFlags wanted, u32 memory_type_bits) {
    for (u32 i = 0; i < properties.memoryTypeCount; ++i) {
        if (((memory_type_bits >> i) & 1) == 0) {
            continue;
        }
        const auto flags = properties.memoryTypes[i].propertyFlags;
        if ((flags & wanted) == wanted) {
            return i;
        }
    }
    return std::nullopt;
}

BufferCache::BufferCache(const Vulkan::Instance& instance_, Vulkan::Scheduler& scheduler_,
                         Vulkan::Runtime& runtime_, AmdGpu::Liverpool* liverpool_,
                         TextureCache& texture_cache_, PageManager& tracker)
    : instance{instance_}, scheduler{scheduler_}, runtime{runtime_},
      staging_pool{runtime_.GetStagingPool()}, liverpool{liverpool_},
      memory{Core::Memory::Instance()}, texture_cache{texture_cache_},
      memory_tracker{std::make_unique<MemoryTracker>(tracker)},
      stream_buffer{instance, scheduler, MemoryType::Stream, STREAM_BUFFER_SIZE},
      gds_buffer{instance, 0, GDS_BUFFER_SIZE, MemoryType::Stream, "GDS Buffer"},
      memory_semaphore{instance} {
    const vk::BufferCreateInfo probe_ci = {
        .flags =
            vk::BufferCreateFlagBits::eSparseBinding | vk::BufferCreateFlagBits::eSparseResidency,
        .size = ARENA_PAGE_SIZE,
        .usage = ARENA_USAGE,
        .sharingMode = vk::SharingMode::eExclusive,
    };
    const vk::DeviceBufferMemoryRequirements req_info = {
        .pCreateInfo = &probe_ci,
    };
    const auto device = instance.GetDevice();
    const auto reqs = device.getBufferMemoryRequirements(req_info).memoryRequirements;
    block_size = Common::AlignUp(std::max<u64>(reqs.alignment, MIN_BLOCK_SIZE), reqs.alignment);
    ASSERT_MSG(std::popcount(block_size) == 1, "Sparse block size {} is not a power of 2",
               block_size);
    block_shift = std::bit_width(block_size) - 1;
    blocks_per_arena_page = ARENA_PAGE_SIZE / block_size;
    blocks_per_arena_page_shift = ARENA_PAGE_BITS - block_shift;
    arena_memory_type_index =
        FindMemoryType(instance.GetMemoryProperties(), vk::MemoryPropertyFlagBits::eDeviceLocal,
                       reqs.memoryTypeBits)
            .value();

    const u64 bda_pagetable_size =
        (blocks_per_arena_page * NUM_ARENA_PAGES) * sizeof(vk::DeviceAddress);
    fault_manager = std::make_unique<FaultManager>(instance, scheduler, *this, block_shift,
                                                   blocks_per_arena_page * NUM_ARENA_PAGES);
    bda_pagetable_buffer = std::make_unique<Buffer>(
        instance, 0, bda_pagetable_size, MemoryType::DeviceLocal, "BDA Page Table Buffer");
    runtime.FillBuffer(bda_pagetable_buffer.get(), 0u, bda_pagetable_size, 0u);
}

BufferCache::~BufferCache() = default;

void BufferCache::TickFrame() {
    if (std::exchange(fault_process_pending, false)) {
        fault_manager->ProcessFaultBuffer();
    }
}

void BufferCache::InvalidateMemory(VAddr device_addr, u64 size, bool assume_locks) {
    memory_tracker->InvalidateRegion(device_addr, size, [this, device_addr, size, assume_locks] {
        ReadMemory(device_addr, size, true, assume_locks);
    });
}

void BufferCache::ReadMemory(VAddr device_addr, u64 size, bool is_write, bool assume_locks) {
    const auto flush_request = [this, device_addr, size, is_write] {
        const u32 first_block = device_addr >> block_shift;
        const u32 last_block = (device_addr + size - 1) >> block_shift;
        const auto* arena = GetArena(first_block, last_block);

        // GPU-modified ranges come as many small scattered islands,
        // so the download is widened to a window around the request
        constexpr u64 WindowSize = 512_KB;
        const VAddr arena_end = arena->cpu_addr + arena->size_bytes;
        const VAddr window_start =
            std::max<VAddr>(Common::AlignDown(device_addr, WindowSize), arena->cpu_addr);
        const VAddr window_end = std::min<VAddr>(
            std::max<VAddr>(window_start + WindowSize, device_addr + size), arena_end);
        DownloadMemory(arena, window_start, window_end - window_start);
        if (is_write) {
            memory_tracker->MarkRegionAsCpuModified(device_addr, size);
        }
    };
    if (assume_locks) {
        flush_request();
    } else {
        liverpool->SendCommand<true>(std::move(flush_request));
    }
}

void BufferCache::DownloadMemory(const Buffer* arena, VAddr device_addr, u64 size) {
    boost::container::small_vector<vk::BufferCopy, 1> copies;
    u64 total_size_bytes = 0;
    const VAddr arena_base = arena->cpu_addr;
    memory_tracker->ForEachDownloadRange<false>(device_addr, size, [&](u64 address, u64 size) {
        const auto add_download = [&](VAddr start, VAddr end) {
            const u64 new_offset = start - arena_base;
            const u64 new_size = end - start;
            copies.push_back(vk::BufferCopy{
                .srcOffset = new_offset,
                .dstOffset = total_size_bytes,
                .size = new_size,
            });
            // Align up to avoid cache conflicts
            constexpr u64 align = 64ULL;
            constexpr u64 mask = ~(align - 1ULL);
            total_size_bytes += (new_size + align - 1) & mask;
        };
        gpu_modified_ranges.ForEachInRange(address, size, add_download);
        gpu_modified_ranges.Subtract(address, size);
    });
    if (total_size_bytes == 0) {
        return;
    }
    const auto download = staging_pool.Request(total_size_bytes, VideoCore::MemoryType::HostCached);
    for (auto& copy : copies) {
        copy.dstOffset += download.offset;
    }
    runtime.CopyBuffer(arena, download.buffer, copies);
    scheduler.Finish();

    download.buffer->Invalidate(download.offset, download.size);
    for (const auto& copy : copies) {
        auto* dst_addr = std::bit_cast<u8*>(arena_base + copy.srcOffset);
        memory->TryWriteBacking(dst_addr, download.mapped + (copy.dstOffset - download.offset),
                                copy.size);
    }
    memory_tracker->UnmarkRegionAsGpuModified(device_addr, size, false);
}

// Copies GPU-written ranges back into guest memory so CPU-side readers see what compute shaders
// produced: the game itself (culling results) and the SRT walker that flattens shader constants.
// One GPU flush covers the whole batch.
// A compute output is declared larger than what its shader writes (inFAMOUS: up to the end of
// the block it sits in), and the game writes the rest of that range itself while the output
// waits for its copy back. Copying the whole range back put the GPU's older bytes over those
// writes: pointers and command words of the game turned into garbage (access violations in the
// game's code and in a copy command of its own, after minutes of shooting). Only bytes the GPU
// changed are written back. I3_MIRROR_WHOLE=1 copies whole ranges as before.
static bool MirrorChangedOnly() {
    static const bool on = Common::ElfInfo::Instance().GameSerial() == "CUSA00004" &&
                           std::getenv("I3_MIRROR_WHOLE") == nullptr;
    return on;
}

void BufferCache::AddPendingMirror(VAddr device_addr, u32 size) {
    pending_mirror_ranges.Add(device_addr, size);
    unissued_mirrors.emplace_back(device_addr, size);
    if (!MirrorChangedOnly()) {
        return;
    }
    // Several hundred outputs wait per frame: found by key, not by walking a list.
    if (size >= MirrorSnapshotMaxSize) {
        return;
    }
    const u32 offset = u32(mirror_snapshot_data.size());
    if (!mirror_snapshots.try_emplace(MirrorSnapshotKey(device_addr, size), offset).second) {
        return;
    }
    mirror_snapshot_data.resize(offset + size);
    memory->CopySparseMemory(device_addr, mirror_snapshot_data.data() + offset, size);
}

void BufferCache::MirrorToGuest(std::span<const std::pair<VAddr, u32>> ranges) {
    if (ranges.empty()) {
        return;
    }
    {
        // Words of compute results left out because the game had rewritten them first.
        static auto last = std::chrono::steady_clock::now();
        if (const auto now = std::chrono::steady_clock::now();
            now - last >= std::chrono::seconds(3)) {
            last = now;
            LOG_ERROR(Render, "copy back: {} result words left out, rewritten by the game", mirror_words_kept);
            mirror_words_kept = 0;
        }
    }
    // Guest memory is about to change under earlier stream copies.
    ++g_stream_epoch;
    u64 total = 0;
    for (const auto& [addr, size] : ranges) {
        total += Common::AlignUp(size, 64);
    }
    // The copy back to guest memory waits for the GPU. A version that did not wait (the copy
    // was written back when the GPU reached it, a frame later) saved 1.5 to 2 ms per frame in
    // inFAMOUS Second Son but wrote results over memory the game had already reused: garbage
    // particle draw arguments, and an access violation after minutes of sustained shooting.
    // I3_ASYNC_MIRROR=1 turns it on again for experiments only.
    static const bool async = Common::ElfInfo::Instance().GameSerial() == "CUSA00004" &&
                              std::getenv("I3_ASYNC_MIRROR") != nullptr;
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
        inflight_mirrors.emplace_back(batch, std::vector(ranges.begin(), ranges.end()));
        unissued_mirrors.clear();
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
                // This copy's ranges may be uploaded from guest memory again. Outputs written
                // since it was issued, and those of copies still on their way, are newer on
                // the GPU than in guest memory and stay protected.
                std::erase_if(inflight_mirrors, [&](const auto& e) { return e.first <= batch; });
                pending_mirror_ranges.Clear();
                for (const auto& [id, later] : inflight_mirrors) {
                    for (const auto& [addr, size] : later) {
                        pending_mirror_ranges.Add(addr, size);
                    }
                }
                for (const auto& [addr, size] : unissued_mirrors) {
                    pending_mirror_ranges.Add(addr, size);
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
        const u8* gpu = download.mapped + cursor;
        cursor += Common::AlignUp(size, 64);
        const auto snapshot = size < MirrorSnapshotMaxSize
                                  ? mirror_snapshots.find(MirrorSnapshotKey(addr, size))
                                  : mirror_snapshots.end();
        if (snapshot == mirror_snapshots.end()) {
            memory->TryWriteBacking(std::bit_cast<u8*>(addr), gpu, size);
            continue;
        }
        const u8* before = mirror_snapshot_data.data() + snapshot->second;
        if (std::memcmp(gpu, before, size) == 0) {
            continue;
        }
        // Changed stretches, joined over gaps under 64 bytes, each written with one call.
        // The copy back lands after the game has been told that its compute work is done
        // (flushing at every such signal halves the frame rate), so the game may already have
        // given the memory another use. A word the game has written since the dispatch is
        // newer than the result and is left alone: it is told from the snapshot taken then.
        static const bool keep_game_writes = std::getenv("I3_MIRROR_CLOBBER") == nullptr;
        static std::vector<u8> current;
        if (keep_game_writes) {
            current.resize(size);
            memory->CopySparseMemory(addr, current.data(), size);
        }
        constexpr u32 Gap = 64;
        u32 start = size;
        u32 end = 0;
        const auto write_stretch = [&] {
            if (start != size) {
                memory->TryWriteBacking(std::bit_cast<u8*>(addr + start), gpu + start,
                                        end - start);
                start = size;
            }
        };
        for (u32 at = 0; at < size; at += 4) {
            const u32 step = std::min(4u, size - at);
            bool changed;
            bool rewritten = false;
            if (step == 4) {
                // Whole words are compared in registers: this loop runs over every pending
                // output of every frame.
                u32 now;
                u32 then;
                std::memcpy(&now, gpu + at, 4);
                std::memcpy(&then, before + at, 4);
                changed = now != then;
                if (keep_game_writes) {
                    u32 held;
                    std::memcpy(&held, current.data() + at, 4);
                    rewritten = held != then;
                }
            } else {
                changed = std::memcmp(gpu + at, before + at, step) != 0;
                rewritten = keep_game_writes &&
                            std::memcmp(current.data() + at, before + at, step) != 0;
            }
            if (rewritten) {
                // Never part of a stretch, not even of a gap inside one.
                write_stretch();
                mirror_words_kept += changed;
                continue;
            }
            if (!changed) {
                continue;
            }
            if (start != size && at - end >= Gap) {
                write_stretch();
            }
            if (start == size) {
                start = at;
            }
            end = at + step;
        }
        write_stretch();
    }
    pending_mirror_ranges.Clear();
    unissued_mirrors.clear();
    inflight_mirrors.clear();
    mirror_snapshots.clear();
    mirror_snapshot_data.clear();
    // Guest memory now holds both the outputs and what the game wrote around them.
    for (const auto& [addr, size] : skipped_uploads) {
        memory_tracker->MarkRegionAsCpuModified(addr, size);
    }
    skipped_uploads.clear();
}

// Debug aid: bytes of the GPU-side copy of a range that differ from guest memory.
u64 BufferCache::DebugMismatch(VAddr device_addr, u32 size) {
    const auto [buffer, offset] = ObtainBuffer(device_addr, size, false);
    const auto download = staging_pool.Request(size, VideoCore::MemoryType::HostCached);
    const vk::BufferCopy copy{offset, download.offset, size};
    runtime.CopyBuffer(buffer, download.buffer, std::span{&copy, 1});
    scheduler.Finish();
    download.buffer->Invalidate(download.offset, size);
    if (std::getenv("SOTC_BUFLOG")) {
        // Keep the GPU side for offline inspection.
        if (FILE* f = std::fopen(fmt::format("bufgpu_{:x}.raw", device_addr).c_str(), "wb")) {
            std::fwrite(download.mapped, 1, size, f);
            std::fclose(f);
        }
    }
    u64 mismatched = 0;
    const u8* guest = std::bit_cast<const u8*>(device_addr);
    for (u32 i = 0; i < size; ++i) {
        mismatched += guest[i] != download.mapped[i];
    }
    return mismatched;
}

std::pair<const Buffer*, u64> BufferCache::ObtainBuffer(VAddr device_addr, u32 size,
                                                        bool is_written, bool is_texel_buffer) {
    Common::FreezeTimer freeze_timer{5};
    // For read-only buffers use device local stream buffer to reduce renderpass breaks.
    static const bool stream_always = std::getenv("SOTC_STREAM_ALWAYS") != nullptr;
    if (!is_written && size <= STREAM_THRESHOLD &&
        (stream_always || !IsRegionGpuModified(device_addr, size))) {
        {
            // Test aid (I3_STREAMSTAT): how many of these copies repeat an address and size
            // already copied since the last Vulkan submit, and how many bytes they carry.
            static const bool stat = std::getenv("I3_STREAMSTAT") != nullptr;
            if (stat) {
                static std::unordered_map<u64, u32> seen;
                static u64 tick = 0, copies = 0, repeats = 0, bytes = 0, repeat_bytes = 0;
                static auto last = std::chrono::steady_clock::now();
                if (const u64 now_tick = scheduler.CurrentTick(); now_tick != tick) {
                    tick = now_tick;
                    seen.clear();
                }
                ++copies;
                bytes += size;
                if (!seen.try_emplace((device_addr << 16) ^ size, 0).second) {
                    ++repeats;
                    repeat_bytes += size;
                }
                if (const auto now = std::chrono::steady_clock::now();
                    now - last >= std::chrono::seconds(3)) {
                    last = now;
                    LOG_ERROR(Render, "stream/3s: copies {} bytes {} repeats {} repeat bytes {}",
                              copies, bytes, repeats, repeat_bytes);
                    copies = repeats = bytes = repeat_bytes = 0;
                }
            }
        }
        // Draws bind the same small read-only buffers over and over: in the heaviest scenes two
        // of three of these copies repeat an address and size copied a moment ago. Until
        // something can have changed that memory (see g_stream_epoch) the earlier copy is
        // still what the GPU has to read, so it is bound again instead of copied again.
        static const bool reuse_on = Common::ElfInfo::Instance().GameSerial() == "CUSA00004" &&
                                     std::getenv("I3_NO_STREAM_REUSE") == nullptr;
        struct ReuseSlot {
            VAddr addr;
            u32 size;
            u32 generation;
            u64 offset;
        };
        static std::vector<ReuseSlot> reuse_slots(1u << 16);
        static u32 reuse_generation = 1;
        static u64 reuse_epoch = 0, reuse_tick = 0, reuse_last_offset = 0;
        ReuseSlot* slot = nullptr;
        if (reuse_on) {
            if (const u64 tick = scheduler.CurrentTick();
                tick != reuse_tick || g_stream_epoch != reuse_epoch) {
                reuse_tick = tick;
                reuse_epoch = g_stream_epoch;
                ++reuse_generation;
            }
            slot = &reuse_slots[((device_addr >> 2) * 0x9E3779B97F4A7C15ULL ^ size) >> 48];
            if (slot->generation == reuse_generation && slot->addr == device_addr &&
                slot->size == size) {
                return {&stream_buffer, slot->offset};
            }
        }
        const auto [data, offset] = stream_buffer.Map(size, instance.UniformMinAlignment());
        memory->CopySparseMemory(device_addr, data, size);
        stream_buffer.Commit();
        if (slot) {
            if (offset < reuse_last_offset) {
                // The stream buffer started over: earlier copies are about to be overwritten.
                ++reuse_generation;
            }
            reuse_last_offset = offset;
            *slot = {device_addr, size, reuse_generation, offset};
        }
        return {&stream_buffer, offset};
    }
    const u64 first_block = device_addr >> block_shift;
    const u64 last_block = (device_addr + size - 1) >> block_shift;
    const auto* arena = GetArena(first_block, last_block);
    {
        Common::FreezeTimer resident_timer{7};
        EnsureResident(arena, first_block, last_block);
    }
    {
        Common::FreezeTimer upload_timer{8};
        SynchronizeMemory(arena, device_addr, size, is_written, is_texel_buffer);
    }
    if (is_written) {
        gpu_modified_ranges.Add(device_addr, size);
        // Temporary: list distinct GPU-written ranges.
        static std::unordered_set<u64> seen;
        if (size >= 0x1000 && seen.size() < 400 && seen.insert(device_addr ^ (u64(size) << 40)).second) {
            LOG_ERROR(Render, "gpu-written buffer {:#x} size {:#x}", device_addr, size);
        }
    }
    return {arena, arena->Offset(device_addr)};
}

void BufferCache::WarmRange(VAddr device_addr, u32 size) {
    boost::container::small_vector<std::pair<VAddr, u64>, 16> parts;
    gpu_modified_ranges.ForEachNotInRange(device_addr, size, [&](VAddr addr, u64 part_size) {
        parts.emplace_back(addr, part_size);
    });
    for (const auto& [addr, part_size] : parts) {
        if (part_size > 64_KB) {
            (void)ObtainBuffer(addr, u32(part_size), false);
        }
    }
}

std::pair<const Buffer*, u64> BufferCache::ObtainBufferForImage(VAddr device_addr, u32 size) {
    if (IsRegionGpuModified(device_addr, size)) {
        return ObtainBuffer(device_addr, size, false);
    }
    const auto staging = staging_pool.Request(size, VideoCore::MemoryType::HostUncached,
                                              instance.StorageMinAlignment());
    memory->CopySparseMemory(device_addr, staging.mapped, staging.size);
    staging.Flush();
    return {staging.buffer, staging.offset};
}

bool BufferCache::IsRegionCpuModified(VAddr addr, size_t size) {
    return memory_tracker->IsRegionCpuModified(addr, size);
}

bool BufferCache::IsRegionGpuModified(VAddr addr, size_t size) {
    return memory_tracker->IsRegionGpuModified(addr, size);
}

void BufferCache::SynchronizeDmaBuffers() {
    fault_process_pending = true;
    for (const auto& range : resident_ranges) {
        const u64 page = range.start >> (ARENA_PAGE_BITS - block_shift);
        const VAddr device_addr = range.start << block_shift;
        const u64 size = (range.end - range.start) << block_shift;
        SynchronizeMemory(address_space[page], device_addr, size, false, false);
    }
}

const Buffer* BufferCache::GetArena(u64 first_block, u64 last_block) {
    const u64 first_page = first_block >> blocks_per_arena_page_shift;
    const u64 last_page = last_block >> blocks_per_arena_page_shift;
    ASSERT_MSG(last_page - first_page <= 1,
               "Buffer request cannot span more than two VA arena pages");

    const auto* first_arena = address_space[first_page];
    const auto* last_arena = address_space[last_page];
    if (first_arena == last_arena) {
        if (!first_arena) {
            const u64 base_block = Common::AlignDownPow2<u64>(first_block, blocks_per_arena_page);
            const u64 num_pages = last_page - first_page + 1;
            const auto* new_arena =
                &arenas.emplace_back(instance, base_block << block_shift,
                                     num_pages << ARENA_PAGE_BITS, MemoryType::Sparse);
            address_space[first_page] = new_arena;
            address_space[last_page] = new_arena;
        }
        return address_space[first_page];
    }

    LOG_WARNING(Render, "Migrating arena");

    const u64 first_addr = first_arena ? first_arena->cpu_addr : (first_page << ARENA_PAGE_BITS);
    const u64 first_size = first_arena ? first_arena->size_bytes : ARENA_PAGE_SIZE;
    const u64 last_size = last_arena ? last_arena->size_bytes : ARENA_PAGE_SIZE;

    const u64 base_block = first_addr >> block_shift;
    const u64 total_size = first_size + last_size;
    const u64 end_block = (first_addr + total_size) >> block_shift;
    auto* new_arena = &arenas.emplace_back(instance, first_addr, total_size, MemoryType::Sparse);
    auto* bind = BindsForArena(new_arena);
    resident_ranges.ForEachInRange(base_block, end_block, [&](const Backing& backing) {
        const u64 start = std::max(base_block, backing.start);
        const u64 end = std::min(end_block, backing.end);
        bind->binds.push_back(vk::SparseMemoryBind{
            .resourceOffset = (start - base_block) << block_shift,
            .size = (end - start) << block_shift,
            .memory = backing.memory,
            .memoryOffset = (backing.offset + start - backing.start) << block_shift,
        });
    });

    u64 base_page = first_addr >> ARENA_PAGE_BITS;
    for (u32 page = 0; page < (first_size >> ARENA_PAGE_BITS); ++page) {
        address_space[base_page + page] = new_arena;
    }
    base_page = last_page;
    for (u32 page = 0; page < (last_size >> ARENA_PAGE_BITS); ++page) {
        address_space[base_page + page] = new_arena;
    }
    return new_arena;
}

void BufferCache::EnsureResident(const Buffer* arena, u64 first_block, u64 last_block) {
    u32 resident_blocks{};
    IntervalList bind_ranges;
    resident_ranges.ForEachGap(first_block, last_block + 1, [&](u64 start, u64 end) {
        resident_blocks += end - start;
        bind_ranges.Add({start, end});
    });

    if (bind_ranges.Empty()) {
        return;
    }

    const vk::MemoryAllocateFlagsInfo alloc_flags = {
        .flags = vk::MemoryAllocateFlagBits::eDeviceAddress,
    };
    const vk::MemoryAllocateInfo alloc_info = {
        .pNext = &alloc_flags,
        .allocationSize = resident_blocks << block_shift,
        .memoryTypeIndex = arena_memory_type_index,
    };
    const auto device_memory = Vulkan::Check(instance.GetDevice().allocateMemory(alloc_info));

    boost::container::small_vector<vk::BufferCopy, 8> copies;
    const auto staging =
        staging_pool.Request(resident_blocks * sizeof(vk::DeviceAddress), MemoryType::HostUncached);

    u64 memory_offset{};
    ArenaBinds* binds = BindsForArena(arena);
    auto* bda_addrs = reinterpret_cast<vk::DeviceAddress*>(staging.mapped);
    u64 offset = staging.offset;
    for (const auto& range : bind_ranges) {
        Backing backing;
        backing.start = range.start;
        backing.end = range.end;
        backing.memory = device_memory;
        backing.offset = memory_offset >> block_shift;
        resident_ranges.Add(backing);

        LOG_DEBUG(Render, "Making range start={}, end={} resident", backing.start, backing.end);

        const auto& bind = binds->binds.emplace_back(vk::SparseMemoryBind{
            .resourceOffset = (range.start << block_shift) - arena->cpu_addr,
            .size = (range.end - range.start) << block_shift,
            .memory = device_memory,
            .memoryOffset = memory_offset,
        });
        memory_offset += bind.size;

        for (u32 block = 0; block < bind.size; block += block_size) {
            *(bda_addrs++) = arena->BufferDeviceAddress() + bind.resourceOffset + block;
        }
        const u64 copy_size = (backing.end - backing.start) * sizeof(vk::DeviceAddress);
        copies.emplace_back(offset, backing.start * sizeof(vk::DeviceAddress), copy_size);
        offset += copy_size;
    }

    staging.Flush();
    runtime.CopyBuffer(staging.buffer, bda_pagetable_buffer.get(), copies);
}

bool BufferCache::SynchronizeMemory(const Buffer* arena, VAddr device_addr, u32 size,
                                    bool is_written, bool is_texel_buffer) {
    boost::container::small_vector<vk::BufferCopy, 4> copies;
    size_t total_size_bytes{};
    memory_tracker->ForEachUploadRange(device_addr, size, is_written, [&](u64 addr, u64 size) {
        // Dirty state is per page. A page the guest wrote to may also hold a compute output
        // that has not been copied back yet; uploading those bytes would replace the GPU's
        // result with what guest memory held before it.
        pending_mirror_ranges.ForEachNotInRange(addr, size, [&](u64 part_addr, u64 part_size) {
            copies.emplace_back(total_size_bytes, part_addr, part_size);
            total_size_bytes += part_size;
        });
        if (MirrorChangedOnly()) {
            pending_mirror_ranges.ForEachInRange(addr, size, [&](u64 part_addr, u64 part_end) {
                skipped_uploads.emplace_back(part_addr, u32(part_end - part_addr));
            });
        }
    });
    if (!copies.empty()) {
        Common::g_upload_bytes += total_size_bytes;
        if (Common::g_freeze_log && total_size_bytes >= (8u << 20)) {
            LOG_ERROR(Render, "big buffer upload: request {:#x} size {} KB written {} texel {} -> "
                              "{} KB in {} ranges, first {:#x} {} KB",
                      device_addr, size >> 10, is_written, is_texel_buffer, total_size_bytes >> 10,
                      copies.size(), u64(copies[0].dstOffset), copies[0].size >> 10);
        }
        const bool timed = Common::g_freeze_log && total_size_bytes >= (64u << 20);
        const auto t0 = std::chrono::steady_clock::now();
        const auto staging = staging_pool.Request(total_size_bytes, MemoryType::HostUncached);
        const auto t1 = std::chrono::steady_clock::now();
        if (total_size_bytes >= (64u << 20)) {
            // A first bind of a heap-sized buffer copies gigabytes in one frame: several
            // threads take 4 MB pieces of it. The walk only reads guest memory.
            struct Piece {
                u64 addr;
                u8* dest;
                u64 size;
            };
            std::vector<Piece> pieces;
            static constexpr u64 PieceSize = 4ull << 20;
            for (const auto& copy : copies) {
                for (u64 done = 0; done < copy.size; done += PieceSize) {
                    pieces.push_back({copy.dstOffset + done, staging.mapped + copy.srcOffset + done,
                                      std::min<u64>(PieceSize, copy.size - done)});
                }
            }
            std::atomic<size_t> next{0};
            const auto work = [&] {
                for (size_t i = next++; i < pieces.size(); i = next++) {
                    memory->CopySparseMemory(pieces[i].addr, pieces[i].dest, pieces[i].size);
                }
            };
            std::array<std::thread, 5> helpers;
            for (auto& helper : helpers) {
                helper = std::thread{work};
            }
            work();
            for (auto& helper : helpers) {
                helper.join();
            }
        }
        for (auto& copy : copies) {
            if (total_size_bytes < (64u << 20)) {
                memory->CopySparseMemory(copy.dstOffset, staging.mapped + copy.srcOffset,
                                         copy.size);
            }
            copy.srcOffset += staging.offset;
            copy.dstOffset -= arena->cpu_addr;
        }
        const auto t2 = std::chrono::steady_clock::now();
        staging.Flush();
        const auto t3 = std::chrono::steady_clock::now();
        runtime.CopyBuffer(staging.buffer, arena, copies);
        if (timed) {
            const auto ms = [](auto a, auto b) {
                return std::chrono::duration_cast<std::chrono::milliseconds>(b - a).count();
            };
            LOG_ERROR(Render, "upload split: {} MB, staging request {} ms, guest copy {} ms, "
                              "flush {} ms, gpu copy record {} ms",
                      total_size_bytes >> 20, ms(t0, t1), ms(t1, t2), ms(t2, t3),
                      ms(t3, std::chrono::steady_clock::now()));
        }
    }
    if (is_texel_buffer && !is_written) {
        return SynchronizeMemoryFromImage(arena, device_addr, size);
    }
    return false;
}

bool BufferCache::SynchronizeMemoryFromImage(const Buffer* arena, VAddr device_addr, u32 size) {
    if (auto type = texture_cache.IsMeta(device_addr)) {
        if (*type == TextureCache::MetaType::HTile) {
            static constexpr u32 ZmaskUncompressed = 0xf;
            runtime.FillBuffer(arena, arena->Offset(device_addr), size, ZmaskUncompressed);
            return true;
        } else {
            LOG_WARNING(Render_Vulkan, "Unhandled metadata type {}", magic_enum::enum_name(*type));
        }
    }
    const ImageId image_id = texture_cache.FindImageFromRange(device_addr, size);
    if (!image_id) {
        return false;
    }
    Image& image = texture_cache.GetImage(image_id);
    ASSERT_MSG(device_addr == image.info.guest_address,
               "Texel buffer aliases image subresources {:x} : {:x}", device_addr,
               image.info.guest_address);
    const u64 arena_offset = arena->Offset(device_addr);
    boost::container::small_vector<vk::BufferImageCopy, 8> buffer_copies;
    for (u32 mip = 0; mip < image.info.resources.levels; mip++) {
        const auto& mip_info = image.info.mips_layout[mip];
        const u32 width = std::max(image.info.size.width >> mip, 1u);
        const u32 height = std::max(image.info.size.height >> mip, 1u);
        const u32 depth = std::max(image.info.size.depth >> mip, 1u);
        if (arena_offset + mip_info.offset + mip_info.size > arena->size_bytes) {
            break;
        }
        buffer_copies.push_back(vk::BufferImageCopy{
            .bufferOffset = mip_info.offset,
            .bufferRowLength = mip_info.pitch,
            .bufferImageHeight = mip_info.height,
            .imageSubresource{
                .aspectMask = image.aspect_mask & ~vk::ImageAspectFlagBits::eStencil,
                .mipLevel = mip,
                .baseArrayLayer = 0,
                .layerCount = image.info.resources.layers,
            },
            .imageOffset = {0, 0, 0},
            .imageExtent = {width, height, depth},
        });
    }
    if (buffer_copies.empty()) {
        return false;
    }
    auto& tile_manager = texture_cache.GetTileManager();
    tile_manager.TileImage(image, buffer_copies, arena, arena_offset);
    return true;
}

void BufferCache::SubmitPendingArenaBinds(Vulkan::SubmitInfo& info) {
    if (pending_binds.empty()) {
        return;
    }

    std::vector<vk::SparseBufferMemoryBindInfo> buffer_binds;
    buffer_binds.reserve(pending_binds.size());

    for (const auto& binds : pending_binds) {
        buffer_binds.emplace_back(vk::SparseBufferMemoryBindInfo{
            .buffer = binds.arena->Handle(),
            .bindCount = static_cast<u32>(binds.binds.size()),
            .pBinds = binds.binds.data(),
        });
    }

    const u64 signal_tick = memory_semaphore.NextTick();
    const auto signal_sema = memory_semaphore.Handle();

    const vk::TimelineSemaphoreSubmitInfo timeline_si = {
        .signalSemaphoreValueCount = 1u,
        .pSignalSemaphoreValues = &signal_tick,
    };

    const vk::BindSparseInfo sparse_info = {
        .pNext = &timeline_si,
        .bufferBindCount = static_cast<u32>(buffer_binds.size()),
        .pBufferBinds = buffer_binds.data(),
        .signalSemaphoreCount = 1u,
        .pSignalSemaphores = &signal_sema,
    };

    info.AddWait(signal_sema, signal_tick);
    auto submit_result = instance.GetGraphicsQueue().bindSparse(sparse_info);
    ASSERT_MSG(submit_result != vk::Result::eErrorDeviceLost, "Device lost during submit");

    pending_binds.clear();
}

} // namespace VideoCore
