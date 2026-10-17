// SPDX-FileCopyrightText: Copyright 2024 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <deque>
#include <span>
#include <tuple>
#include <utility>
#include <boost/container/small_vector.hpp>

#include "common/interval_set.h"
#include "common/types.h"
#include "common/unique_function.h"
#include "core/memory.h"
#include "video_core/buffer_cache/buffer.h"
#include "video_core/buffer_cache/fault_manager.h"
#include "video_core/buffer_cache/range_set.h"
#include "video_core/renderer_vulkan/vk_semaphore.h"

namespace AmdGpu {
struct Liverpool;
}

namespace Core {
class MemoryManager;
}

namespace Vulkan {
class GraphicsPipeline;
struct SubmitInfo;
class Runtime;
class StagingBufferPool;
} // namespace Vulkan

namespace VideoCore {

class TextureCache;
class MemoryTracker;
class PageManager;

class BufferCache {
    static constexpr u64 ADDRESS_SPACE_BITS = 40;
    static constexpr u64 ARENA_PAGE_BITS = 32;
    static constexpr u64 ARENA_PAGE_SIZE = u64{1} << ARENA_PAGE_BITS;
    static constexpr u64 NUM_ARENA_PAGES = u64{1} << (ADDRESS_SPACE_BITS - ARENA_PAGE_BITS);
    static constexpr u64 MIN_BLOCK_SIZE = 16_KB;
    static constexpr u64 STREAM_THRESHOLD = 16_KB;

public:
    explicit BufferCache(const Vulkan::Instance& instance, Vulkan::Scheduler& scheduler,
                         Vulkan::Runtime& runtime, AmdGpu::Liverpool* liverpool,
                         TextureCache& texture_cache, PageManager& tracker);
    ~BufferCache();

    /// Returns a pointer to GDS device local buffer.
    [[nodiscard]] const Buffer* GetGdsBuffer() const noexcept {
        return &gds_buffer;
    }

    [[nodiscard]] const Buffer* GetNullIndexBuffer() const noexcept {
        return null_index_buffer.get();
    }

    /// Retrieves the device local DBA page table buffer.
    [[nodiscard]] Buffer* GetBdaPageTableBuffer() noexcept {
        return bda_pagetable_buffer.get();
    }

    /// Retrieves the fault buffer.
    [[nodiscard]] Buffer* GetFaultBuffer() noexcept {
        return fault_manager->GetFaultBuffer();
    }

    /// Retrieves the stream buffer.
    [[nodiscard]] StreamBuffer& GetStreamBuffer() noexcept {
        return stream_buffer;
    }

    /// Returns minimum granularity of a sparse memory bind.
    u32 GetSparsePageShift() const noexcept {
        return block_shift;
    }

    void TickFrame();

    /// Invalidates any buffer in the logical page range.
    void InvalidateMemory(VAddr device_addr, u64 size, bool assume_locks = false);

    /// Make committed image bytes visible to subsequent buffer uploads without dropping GPU ranges.
    void NotifyImageReadback(VAddr device_addr, u64 size);

    /// Flushes any GPU modified buffer in the logical page range back to CPU memory.
    void ReadMemory(VAddr device_addr, u64 size, bool is_write = false, bool assume_locks = false);

    /// Finds a buffer for the specified region.
    [[nodiscard]] std::pair<const Buffer*, u64> ObtainBuffer(VAddr device_addr, u32 size,
                                                             bool is_written,
                                                             bool is_texel_buffer = false);

    /// Uploads what the game wrote in a range ahead of its use. Ranges the GPU has written
    /// are left out: their pages may be marked as written by the game too, and uploading
    /// them would put old game bytes over the GPU's results.
    void WarmRange(VAddr device_addr, u32 size);

    /// Attempts to obtain a buffer without modifying the cache contents.
    [[nodiscard]] std::pair<const Buffer*, u64> ObtainBufferForImage(VAddr device_addr, u32 size);

    /// Return true when a region is modified from the CPU
    [[nodiscard]] bool IsRegionCpuModified(VAddr addr, size_t size);

    /// Return true when a region is modified from the GPU
    [[nodiscard]] bool IsRegionGpuModified(VAddr addr, size_t size);

    /// Synchronizes all buffers needed for DMA.
    void SynchronizeDmaBuffers();

    /// Commits pending sparse buffer memory binds. Must be called before every scheduler submit.
    void SubmitPendingArenaBinds(Vulkan::SubmitInfo& info);

    u64 DebugMismatch(VAddr device_addr, u32 size);

    /// Copies GPU-written ranges back into guest memory with a single flush.
    /// `partial`: only these outputs, now and blocking; everything else that is pending stays
    /// pending, and the snapshots of these are brought up to date so that the later full
    /// copy back finds nothing left to write for them.
    void MirrorToGuest(std::span<const std::pair<VAddr, u32>> ranges, bool partial = false);

    /// Marks a range as written by the GPU and not yet copied back to guest memory.
    void AddPendingMirror(VAddr device_addr, u32 size);

    /// Copies a few pending outputs back without blocking: the copy is submitted now, and
    /// when the GPU has run it the results are written to guest memory and `done` is called
    /// (from PopPendingOperations on the command thread).
    void MirrorUrgentAsync(std::span<const std::pair<VAddr, u32>> ranges,
                           Common::UniqueFunction<void>&& done);

    /// Asks for the GPU's bytes of a pending output to be kept at the next copy back (see
    /// TakeCaptured); used to predict the next frame's value of small counters.
    void RequestCapture(VAddr device_addr, u32 size, u64 key);
    /// Captured results since the last call: key and bytes.
    std::vector<std::pair<u64, std::vector<u8>>> TakeCaptured();

private:
    struct ArenaBinds {
        const Buffer* arena;
        boost::container::small_vector<vk::SparseMemoryBind, 32> binds;
    };

    ArenaBinds* BindsForArena(const Buffer* arena) {
        auto it = std::ranges::find(pending_binds, arena, &ArenaBinds::arena);
        if (it != pending_binds.end()) {
            return std::addressof(*it);
        }
        return &pending_binds.emplace_back(arena);
    }

    const Buffer* GetArena(u64 first_block, u64 last_block);

    void EnsureResident(const Buffer* arena, u64 first_block, u64 last_block);

    void DownloadMemory(const Buffer* arena, VAddr device_addr, u64 size);

    std::vector<Core::ReadbackMapping> CaptureMirrorMappings(
        std::span<const std::pair<VAddr, u32>> ranges);
    u64 ReserveMirrorRange(u64 size);
    u64 TrackMirrorRange(u64 offset, u64 size);
    void ReleaseMirrorRange(u64 id);

    bool SynchronizeMemory(const Buffer* arena, VAddr device_addr, u32 size, bool is_written,
                           bool is_texel_buffer);

    bool SynchronizeMemoryFromImage(const Buffer* arena, VAddr device_addr, u32 size);

    const Vulkan::Instance& instance;
    Vulkan::Scheduler& scheduler;
    Vulkan::Runtime& runtime;
    Vulkan::StagingBufferPool& staging_pool;
    AmdGpu::Liverpool* liverpool;
    Core::MemoryManager* memory;
    TextureCache& texture_cache;
    std::unique_ptr<MemoryTracker> memory_tracker;

    StreamBuffer stream_buffer;
    std::vector<std::tuple<VAddr, u32, u64>> capture_requests;
    std::vector<std::pair<u64, std::vector<u8>>> captured;
    Buffer gds_buffer;
    std::unique_ptr<Buffer> null_index_buffer;
    RangeSet gpu_modified_ranges;
    /// Compute outputs that are newer on the GPU than in guest memory, until MirrorToGuest
    /// copies them back. Uploads must leave them alone.
    RangeSet pending_mirror_ranges;
    u64 mirror_batch = 0;
    /// Download target of the non-blocking mirror, used as a ring.
    static constexpr u64 MIRROR_BUFFER_SIZE = 32ULL << 20;
    std::unique_ptr<Buffer> mirror_buffer;
    u64 mirror_offset = 0;
    struct MirrorReservation {
        u64 id;
        u64 offset;
        u64 size;
        u64 copy_tick;
    };
    u64 next_mirror_reservation{};
    std::vector<MirrorReservation> mirror_reservations;
    /// Counts full copy backs; a deferred partial one from before the last full one has
    /// nothing left to write.
    u64 mirror_generation = 0;
    /// GPU ticks of the copy backs still on their way, oldest first.
    std::deque<u64> inflight_ticks;
    u32 mirrors_in_flight = 0;
    /// Ranges added since the last copy was issued, and the ranges of each copy still on its
    /// way: together they are what pending_mirror_ranges has to keep protecting when one
    /// copy lands.
    std::vector<std::pair<VAddr, u32>> unissued_mirrors;
    std::deque<std::pair<u64, std::vector<std::pair<VAddr, u32>>>> inflight_mirrors;
    /// What guest memory held in each pending output when its shader ran. The copy back
    /// writes only what the GPU changed against it.
    /// Keyed by address and size, the value is the offset into mirror_snapshot_data.
    static constexpr u32 MirrorSnapshotMaxSize = 1u << 20;
    static u64 MirrorSnapshotKey(VAddr addr, u32 size) {
        return (addr << 20) | size;
    }
    std::unordered_map<u64, u32> mirror_snapshots;
    std::map<std::pair<VAddr, u32>, Core::ReadbackMapping> mirror_mappings;
    std::vector<u8> mirror_snapshot_data;
    /// Parts of pending outputs an upload left out: their pages lost their written-by-the-game
    /// mark with that upload and get it back once the outputs are copied back.
    std::vector<std::pair<VAddr, u32>> skipped_uploads;

    std::unique_ptr<FaultManager> fault_manager;
    std::unique_ptr<Buffer> bda_pagetable_buffer;
    bool fault_process_pending{};

    std::array<const Buffer*, NUM_ARENA_PAGES> address_space{};
    std::deque<Buffer> arenas;
    std::vector<ArenaBinds> pending_binds;
    Vulkan::Semaphore memory_semaphore;

    struct Backing : public Interval {
        vk::DeviceMemory memory;
        u64 offset;
        constexpr bool CanMergeWith(const Backing& other) const noexcept {
            return memory == other.memory && offset + (end - start) == other.offset;
        }
        constexpr Backing SubRange(u64 a, u64 b) const noexcept {
            return {{a, b}, memory, offset + (a - start)};
        }
    };
    IntervalList<Backing> resident_ranges;

    u32 arena_memory_type_index{};
    u32 block_size{};
    u32 block_shift{};
    u32 blocks_per_arena_page{};
    u32 blocks_per_arena_page_shift{};
};

} // namespace VideoCore
