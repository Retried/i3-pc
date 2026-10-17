// SPDX-License-Identifier: GPL-2.0-or-later

#include <algorithm>
#include <cstdlib>
#include <immintrin.h>

#include "common/assert.h"
#include "common/logging/log.h"
#include "common/thread.h"
#include "video_core/renderer_vulkan/vk_command_stream.h"

namespace Vulkan {

CommandStream::CommandStream() {
    descriptor_cache_enabled = std::getenv("SHAD_DISABLE_PUSH_DESCRIPTOR_CACHE") == nullptr;
    descriptor_stats_enabled = std::getenv("SHAD_PUSH_DESCRIPTOR_STATS") != nullptr;
    last_descriptor_report = std::chrono::steady_clock::now();
    command_cache_enabled = std::getenv("SHAD_DISABLE_COMMAND_CACHE") == nullptr;
    command_stats_enabled = std::getenv("SHAD_COMMAND_STREAM_STATS") != nullptr;
    last_command_report = std::chrono::steady_clock::now();
    const char* setting = std::getenv("SOTC_WORKER_RECORD");
    async = setting == nullptr || std::atoi(setting) != 0;
    if (async) {
        worker = std::jthread([this](std::stop_token stop) { WorkerLoop(stop); });
    }
}

void CommandStream::InvalidateCommandCache(CommandInvalidation reason) {
    cached_pipelines.fill(nullptr);
    index_binding.valid = false;
    vertex_binding.valid = false;
    push_constants.valid = false;
    if (command_stats_enabled) {
        ++command_stats.invalidations[static_cast<size_t>(reason)];
    }
}

void CommandStream::CheckResourceChanges() {
    if (descriptor_resources_changed.load(std::memory_order_acquire) &&
        descriptor_resources_changed.exchange(false, std::memory_order_acq_rel)) {
        InvalidateDescriptorCache(DescriptorInvalidation::ResourceLifetime);
        InvalidateCommandCache(CommandInvalidation::ResourceLifetime);
    }
}

void CommandStream::ReportCommandStats() {
    if (!command_stats_enabled) {
        return;
    }
    const auto now = std::chrono::steady_clock::now();
    if (now - last_command_report < std::chrono::seconds(3)) {
        return;
    }
    last_command_report = now;
    const auto& s = command_stats;
    LOG_INFO(Render_Vulkan,
             "Command stream total: stream {} cache {} worker {} emitted {} command_bytes {} "
             "copied_bytes {} enqueue_ns {} inline_ns {} drains {} drain_ns {} worker_commands {} "
             "worker_chunks {} worker_ns {}",
             static_cast<const void*>(this), command_cache_enabled, async, s.emitted,
             s.command_bytes, s.copied_bytes, s.enqueue_ns, s.inline_ns, s.drains, s.drain_ns,
             s.worker_commands.load(), s.worker_chunks.load(), s.worker_ns.load());
    static constexpr std::array names{"pipeline", "index", "vertex", "constants"};
    for (size_t i = 0; i < names.size(); ++i) {
        LOG_INFO(Render_Vulkan,
                 "Command filter total: stream {} kind {} calls {} skipped {} producer_ns {}",
                 static_cast<const void*>(this), names[i], s.calls[i], s.skipped[i],
                 s.producer_ns[i]);
    }
    LOG_INFO(Render_Vulkan,
             "Command invalidations total: stream {} target {} session {} generic {} direct {} "
             "lifetime {} unsupported {} dynamic_pipeline {}",
             static_cast<const void*>(this), s.invalidations[0], s.invalidations[1],
             s.invalidations[2], s.invalidations[3], s.invalidations[4], s.invalidations[5],
             s.dynamic_invalidations);
}

void CommandStream::bindPipeline(vk::PipelineBindPoint point, vk::Pipeline pipeline) {
    constexpr auto kind = static_cast<size_t>(FilteredCommand::Pipeline);
    const CommandTimer timer{command_stats_enabled, command_stats.producer_ns[kind]};
    if (command_stats_enabled) {
        ++command_stats.calls[kind];
    }
    CheckResourceChanges();
    if (command_cache_enabled) {
        if (pipeline && (point == vk::PipelineBindPoint::eGraphics ||
                         point == vk::PipelineBindPoint::eCompute)) {
            auto& last = cached_pipelines[point == vk::PipelineBindPoint::eCompute ? 1 : 0];
            if (last == pipeline) {
                if (command_stats_enabled) {
                    ++command_stats.skipped[kind];
                }
                return;
            }
            last = pipeline;
        } else {
            InvalidateCommandCache(CommandInvalidation::Unsupported);
        }
    }
    Push(0, [=](vk::CommandBuffer c) { c.bindPipeline(point, pipeline); });
}

bool CommandStream::UpdateIndexBinding(vk::Buffer buffer, vk::DeviceSize offset,
                                       vk::DeviceSize size, vk::IndexType type, bool sized) {
    constexpr auto kind = static_cast<size_t>(FilteredCommand::Index);
    if (command_stats_enabled) {
        ++command_stats.calls[kind];
    }
    CheckResourceChanges();
    if (!command_cache_enabled) {
        return false;
    }
    const auto& last = index_binding;
    const bool same = last.valid && last.buffer == buffer && last.offset == offset &&
                      last.size == size && last.type == type && last.sized == sized;
    index_binding = {buffer, offset, size, type, sized, true};
    if (same && command_stats_enabled) {
        ++command_stats.skipped[kind];
    }
    return same;
}

void CommandStream::bindIndexBuffer(vk::Buffer buffer, vk::DeviceSize offset, vk::IndexType type) {
    const CommandTimer timer{
        command_stats_enabled,
        command_stats.producer_ns[static_cast<size_t>(FilteredCommand::Index)]};
    if (!UpdateIndexBinding(buffer, offset, 0, type, false)) {
        Push(0, [=](vk::CommandBuffer c) { c.bindIndexBuffer(buffer, offset, type); });
    }
}

void CommandStream::bindIndexBuffer2KHR(vk::Buffer buffer, vk::DeviceSize offset,
                                        vk::DeviceSize size, vk::IndexType type) {
    const CommandTimer timer{
        command_stats_enabled,
        command_stats.producer_ns[static_cast<size_t>(FilteredCommand::Index)]};
    if (!UpdateIndexBinding(buffer, offset, size, type, true)) {
        Push(0, [=](vk::CommandBuffer c) { c.bindIndexBuffer2KHR(buffer, offset, size, type); });
    }
}

void CommandStream::bindVertexBuffers(u32 first, u32 count, const vk::Buffer* buffers,
                                      const vk::DeviceSize* offsets) {
    constexpr auto kind = static_cast<size_t>(FilteredCommand::Vertex);
    const CommandTimer timer{command_stats_enabled, command_stats.producer_ns[kind]};
    if (command_stats_enabled) {
        ++command_stats.calls[kind];
    }
    CheckResourceChanges();
    if (command_cache_enabled) {
        auto& last = vertex_binding;
        if (count && count <= MaxCachedVertexBuffers && first <= MaxCachedVertexBuffers - count &&
            buffers && offsets) {
            if (last.valid && last.first == first && last.count == count &&
                std::equal(buffers, buffers + count, last.buffers.begin()) &&
                std::equal(offsets, offsets + count, last.offsets.begin())) {
                if (command_stats_enabled) {
                    ++command_stats.skipped[kind];
                }
                return;
            }
            std::copy_n(buffers, count, last.buffers.begin());
            std::copy_n(offsets, count, last.offsets.begin());
            last.first = first;
            last.count = count;
            last.valid = true;
        } else {
            last.valid = false;
        }
    }
    Reserve(count * (sizeof(vk::Buffer) + sizeof(vk::DeviceSize)));
    const auto* b = Copy(buffers, count);
    const auto* o = Copy(offsets, count);
    Push(0, [=](vk::CommandBuffer c) { c.bindVertexBuffers(first, count, b, o); });
}

void CommandStream::pushConstants(vk::PipelineLayout layout, vk::ShaderStageFlags stages,
                                  u32 offset, u32 size, const void* values) {
    constexpr auto kind = static_cast<size_t>(FilteredCommand::Constants);
    const CommandTimer timer{command_stats_enabled, command_stats.producer_ns[kind]};
    if (command_stats_enabled) {
        ++command_stats.calls[kind];
    }
    CheckResourceChanges();
    if (command_cache_enabled) {
        auto& last = push_constants;
        if (layout && stages && values && size && size <= last.bytes.size() && offset % 4 == 0 &&
            size % 4 == 0) {
            if (last.valid && last.layout == layout && last.stages == stages &&
                last.offset == offset && last.size == size &&
                std::memcmp(last.bytes.data(), values, size) == 0) {
                if (command_stats_enabled) {
                    ++command_stats.skipped[kind];
                }
                return;
            }
            std::memcpy(last.bytes.data(), values, size);
            last.layout = layout;
            last.stages = stages;
            last.offset = offset;
            last.size = size;
            last.valid = true;
        } else {
            last.valid = false;
        }
    }
    Reserve(size);
    const auto* data = Copy(static_cast<const u8*>(values), size);
    Push(0, [=](vk::CommandBuffer c) { c.pushConstants(layout, stages, offset, size, data); });
}

void CommandStream::InvalidateDescriptorCache(DescriptorInvalidation reason) {
    if (descriptor_stats_enabled) {
        ++descriptor_stats.invalidations[static_cast<size_t>(reason)];
    }
    for (auto& cache : descriptor_caches) {
        cache.layout = nullptr;
        cache.hit_run = 0;
    }
}

void CommandStream::ReportDescriptorCacheStats() {
    if (!descriptor_stats_enabled) {
        return;
    }
    const auto now = std::chrono::steady_clock::now();
    if (now - last_descriptor_report < std::chrono::seconds(3)) {
        return;
    }
    last_descriptor_report = now;
    const auto& s = descriptor_stats;
    LOG_INFO(Render_Vulkan,
             "Push descriptors total: cache {} worker {} calls {} cacheable {} writes {} "
             "forwarded {} skipped_calls {} max_hit_run {} layout_changes {}",
             descriptor_cache_enabled, async, s.calls, s.cacheable_calls, s.writes, s.forwarded,
             s.skipped_calls, s.max_hit_run, s.layout_changes);
    LOG_INFO(Render_Vulkan,
             "Push descriptor invalidations total: target {} session {} sets {} generic {} "
             "direct {} unsupported {} lifetime {}",
             s.invalidations[0], s.invalidations[1], s.invalidations[2], s.invalidations[3],
             s.invalidations[4], s.invalidations[5], s.invalidations[6]);
}

bool CommandStream::CachedDescriptor::Update(const vk::WriteDescriptorSet& write) {
    bool same = valid && type == write.descriptorType;
    switch (write.descriptorType) {
    case vk::DescriptorType::eSampler:
        same &= image.sampler == write.pImageInfo->sampler;
        image.sampler = write.pImageInfo->sampler;
        break;
    case vk::DescriptorType::eCombinedImageSampler:
        same &= image == *write.pImageInfo;
        image = *write.pImageInfo;
        break;
    case vk::DescriptorType::eSampledImage:
    case vk::DescriptorType::eStorageImage:
    case vk::DescriptorType::eInputAttachment:
        same &= image.imageView == write.pImageInfo->imageView &&
                image.imageLayout == write.pImageInfo->imageLayout;
        image.imageView = write.pImageInfo->imageView;
        image.imageLayout = write.pImageInfo->imageLayout;
        break;
    case vk::DescriptorType::eUniformBuffer:
    case vk::DescriptorType::eStorageBuffer:
        same &= buffer == *write.pBufferInfo;
        buffer = *write.pBufferInfo;
        break;
    case vk::DescriptorType::eUniformTexelBuffer:
    case vk::DescriptorType::eStorageTexelBuffer:
        same &= texel == *write.pTexelBufferView;
        texel = *write.pTexelBufferView;
        break;
    default:
        return false;
    }
    type = write.descriptorType;
    valid = true;
    return same;
}

static bool CanCacheDescriptor(const vk::WriteDescriptorSet& write) {
    if (write.pNext || write.descriptorCount != 1 || write.dstArrayElement != 0) {
        return false;
    }
    switch (write.descriptorType) {
    case vk::DescriptorType::eSampler:
    case vk::DescriptorType::eCombinedImageSampler:
    case vk::DescriptorType::eSampledImage:
    case vk::DescriptorType::eStorageImage:
    case vk::DescriptorType::eInputAttachment:
        return write.pImageInfo != nullptr;
    case vk::DescriptorType::eUniformBuffer:
    case vk::DescriptorType::eStorageBuffer:
        return write.pBufferInfo != nullptr;
    case vk::DescriptorType::eUniformTexelBuffer:
    case vk::DescriptorType::eStorageTexelBuffer:
        return write.pTexelBufferView != nullptr;
    default:
        return false;
    }
}

CommandStream::~CommandStream() {
    if (async) {
        Drain();
        worker.request_stop();
        wake.notify_all();
    }
}

void CommandStream::Reserve(size_t aux_bytes) {
    if (!async) {
        return;
    }
    Chunk& chunk = chunks[write_index];
    ASSERT_MSG(aux_bytes + 256 < Chunk::AuxBytes, "Command data too large for the stream");
    // Room for the copied data (with alignment slack) and for the largest record.
    if (chunk.command_used + 1024 > Chunk::CommandBytes ||
        chunk.aux_used + aux_bytes + 256 > Chunk::AuxBytes) {
        Publish();
    }
    chunks[write_index].target = target;
}

void CommandStream::Publish() {
    Chunk& chunk = chunks[write_index];
    if (chunk.command_used == 0) {
        chunk.aux_used = 0;
        return;
    }
    const u64 sequence = published.load(std::memory_order_relaxed) + 1;
    {
        // The lock pairs with the worker's wait so a wake-up cannot be missed.
        std::scoped_lock lock{mutex};
        published.store(sequence, std::memory_order_release);
    }
    wake.notify_one();
    // The next chunk in the ring is free once the worker is less than a full ring behind.
    while (sequence - completed.load(std::memory_order_acquire) >= NumChunks) {
        _mm_pause();
    }
    write_index = static_cast<u32>(sequence % NumChunks);
    chunks[write_index].command_used = 0;
    chunks[write_index].aux_used = 0;
    chunks[write_index].target = target;
}

void CommandStream::Drain() {
    const CommandTimer timer{command_stats_enabled, command_stats.drain_ns};
    if (command_stats_enabled) {
        ++command_stats.drains;
    }
    if (!async) {
        return;
    }
    Publish();
    const u64 goal = published.load(std::memory_order_relaxed);
    if (completed.load(std::memory_order_acquire) == goal) {
        return;
    }
    ++waited_drains;
    u32 spins = 0;
    while (completed.load(std::memory_order_acquire) != goal) {
        if (++spins < 4000) {
            _mm_pause();
        } else {
            std::this_thread::yield();
        }
    }
}

void CommandStream::WorkerLoop(std::stop_token stop) {
    Common::SetCurrentThreadName("shadPS4:GpuCommandRecorder");
    u64 next = 0;
    while (!stop.stop_requested()) {
        // Commands arrive in bursts a few microseconds apart: look again for a short while
        // before sleeping, so the producer rarely pays for a wake-up.
        u32 spins = 0;
        while (published.load(std::memory_order_acquire) == next && spins < 20000) {
            _mm_pause();
            ++spins;
        }
        if (published.load(std::memory_order_acquire) == next) {
            std::unique_lock lock{mutex};
            wake.wait(lock, stop,
                      [&] { return published.load(std::memory_order_acquire) != next; });
            if (stop.stop_requested()) {
                break;
            }
        }
        const Chunk& chunk = chunks[next % NumChunks];
        const auto record_start = command_stats_enabled ? std::chrono::steady_clock::now()
                                                        : std::chrono::steady_clock::time_point{};
        u64 recorded = 0;
        const u8* cursor = chunk.commands.get();
        const u8* const end = cursor + chunk.command_used;
        while (cursor < end) {
            const auto* record = reinterpret_cast<const Record*>(cursor);
            record->invoke(record + 1, chunk.target);
            cursor += record->size;
            ++recorded;
        }
        if (command_stats_enabled) {
            command_stats.worker_commands.fetch_add(recorded, std::memory_order_relaxed);
            command_stats.worker_chunks.fetch_add(1, std::memory_order_relaxed);
            command_stats.worker_ns.fetch_add(std::chrono::duration_cast<std::chrono::nanoseconds>(
                                                  std::chrono::steady_clock::now() - record_start)
                                                  .count(),
                                              std::memory_order_relaxed);
        }
        ++next;
        completed.store(next, std::memory_order_release);
    }
}

void CommandStream::pushDescriptorSetKHR(vk::PipelineBindPoint point, vk::PipelineLayout layout,
                                         u32 set, std::span<const vk::WriteDescriptorSet> writes) {
    CheckResourceChanges();
    if (descriptor_stats_enabled) {
        ++descriptor_stats.calls;
        descriptor_stats.writes += writes.size();
    }
    auto& changed = changed_descriptor_writes;
    const bool cacheable =
        descriptor_cache_enabled && !writes.empty() && set == 0 &&
        (point == vk::PipelineBindPoint::eGraphics || point == vk::PipelineBindPoint::eCompute) &&
        writes.size() <= changed.size() && std::ranges::all_of(writes, [](const auto& write) {
            return write.dstBinding < MaxCachedDescriptorBindings && CanCacheDescriptor(write);
        });
    if (cacheable) {
        if (descriptor_stats_enabled) {
            ++descriptor_stats.cacheable_calls;
        }
        auto& cache = descriptor_caches[point == vk::PipelineBindPoint::eCompute ? 1 : 0];
        if (cache.layout != layout) {
            if (descriptor_stats_enabled) {
                ++descriptor_stats.layout_changes;
            }
            cache.layout = layout;
            cache.hit_run = 0;
            for (auto& binding : cache.bindings) {
                binding.valid = false;
            }
        }
        size_t count = 0;
        for (const auto& write : writes) {
            if (!cache.bindings[write.dstBinding].Update(write)) {
                changed[count++] = write;
            }
        }
        if (count == 0) {
            if (descriptor_stats_enabled) {
                ++descriptor_stats.skipped_calls;
                descriptor_stats.max_hit_run =
                    std::max(descriptor_stats.max_hit_run, ++cache.hit_run);
            }
            return;
        }
        cache.hit_run = 0;
        writes = std::span{changed}.first(count);
    } else if (descriptor_cache_enabled) {
        InvalidateDescriptorCache(DescriptorInvalidation::Unsupported);
    }
    if (descriptor_stats_enabled) {
        descriptor_stats.forwarded += writes.size();
    }
    if (!async) {
        target.pushDescriptorSetKHR(point, layout, set, static_cast<u32>(writes.size()),
                                    writes.data());
        return;
    }
    // The writes point at arrays the caller reuses for the next draw: copy those too.
    size_t bytes = writes.size_bytes();
    bool chained = false;
    for (const auto& write : writes) {
        chained |= write.pNext != nullptr;
        bytes += write.descriptorCount *
                     std::max(sizeof(vk::DescriptorImageInfo), sizeof(vk::DescriptorBufferInfo)) +
                 16;
    }
    if (chained || bytes > MaxQueuedData) {
        // Chained, or too much to copy into a chunk: record it in place, in its turn.
        Drain();
        target.pushDescriptorSetKHR(point, layout, set, static_cast<u32>(writes.size()),
                                    writes.data());
        return;
    }
    Reserve(bytes);
    auto* copy = const_cast<vk::WriteDescriptorSet*>(Copy(writes.data(), writes.size()));
    for (size_t i = 0; i < writes.size(); i++) {
        const auto& write = writes[i];
        if (write.pImageInfo) {
            copy[i].pImageInfo = Copy(write.pImageInfo, write.descriptorCount);
        }
        if (write.pBufferInfo) {
            copy[i].pBufferInfo = Copy(write.pBufferInfo, write.descriptorCount);
        }
        if (write.pTexelBufferView) {
            copy[i].pTexelBufferView = Copy(write.pTexelBufferView, write.descriptorCount);
        }
    }
    const u32 count = static_cast<u32>(writes.size());
    Push(0, [=](vk::CommandBuffer c) { c.pushDescriptorSetKHR(point, layout, set, count, copy); });
}

void CommandStream::beginRendering(const vk::RenderingInfo& info) {
    if (!async) {
        target.beginRendering(info);
        return;
    }
    if (info.pNext != nullptr) {
        Drain();
        target.beginRendering(info);
        return;
    }
    Reserve(sizeof(info) + (info.colorAttachmentCount + 2) * sizeof(vk::RenderingAttachmentInfo));
    auto* copy = const_cast<vk::RenderingInfo*>(Copy(&info, 1));
    copy->pColorAttachments = Copy(info.pColorAttachments, info.colorAttachmentCount);
    if (info.pDepthAttachment) {
        copy->pDepthAttachment = Copy(info.pDepthAttachment, 1);
    }
    if (info.pStencilAttachment) {
        copy->pStencilAttachment = Copy(info.pStencilAttachment, 1);
    }
    Push(0, [=](vk::CommandBuffer c) { c.beginRendering(*copy); });
}

void CommandStream::pipelineBarrier2(const vk::DependencyInfo& info) {
    if (!async) {
        target.pipelineBarrier2(info);
        return;
    }
    const size_t bytes = sizeof(info) + info.memoryBarrierCount * sizeof(vk::MemoryBarrier2) +
                         info.bufferMemoryBarrierCount * sizeof(vk::BufferMemoryBarrier2) +
                         info.imageMemoryBarrierCount * sizeof(vk::ImageMemoryBarrier2);
    // A chained structure cannot be copied blindly, and a very long barrier list (one entry per
    // mip and layer of a large image) does not fit a chunk: both are recorded in place.
    if (info.pNext != nullptr || bytes > MaxQueuedData) {
        Drain();
        target.pipelineBarrier2(info);
        return;
    }
    Reserve(bytes);
    auto* copy = const_cast<vk::DependencyInfo*>(Copy(&info, 1));
    copy->pMemoryBarriers = Copy(info.pMemoryBarriers, info.memoryBarrierCount);
    copy->pBufferMemoryBarriers = Copy(info.pBufferMemoryBarriers, info.bufferMemoryBarrierCount);
    copy->pImageMemoryBarriers = Copy(info.pImageMemoryBarriers, info.imageMemoryBarrierCount);
    Push(0, [=](vk::CommandBuffer c) { c.pipelineBarrier2(*copy); });
}

} // namespace Vulkan
