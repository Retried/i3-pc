// SPDX-FileCopyrightText: Copyright 2020 yuzu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <chrono>
#include <cstdlib>
#include <limits>
#include <immintrin.h>
#include "common/elf_info.h"
#include "common/logging/log.h"
#include "video_core/renderer_vulkan/vk_instance.h"
#include "video_core/renderer_vulkan/vk_semaphore.h"

#include "common/assert.h"

namespace Vulkan {

namespace {
class SyncTimer {
public:
    SyncTimer(bool enabled, std::atomic<u64>& calls, std::atomic<u64>& elapsed)
        : enabled{enabled}, calls{calls}, elapsed{elapsed} {
        if (enabled) {
            start = std::chrono::steady_clock::now();
        }
    }

    ~SyncTimer() {
        if (enabled) {
            calls.fetch_add(1, std::memory_order_relaxed);
            elapsed.fetch_add(std::chrono::duration_cast<std::chrono::nanoseconds>(
                                  std::chrono::steady_clock::now() - start)
                                  .count(),
                              std::memory_order_relaxed);
        }
    }

private:
    bool enabled;
    std::atomic<u64>& calls;
    std::atomic<u64>& elapsed;
    std::chrono::steady_clock::time_point start{};
};
} // namespace

constexpr u64 WAIT_TIMEOUT = std::numeric_limits<u64>::max();

Semaphore::Semaphore(const Instance& instance_) : instance{instance_} {
    optimize_refresh = std::getenv("SHAD_DISABLE_GPU_SCHEDULER_OPT") == nullptr;
    sync_stats_enabled = std::getenv("SHAD_GPU_SYNC_STATS") != nullptr;
    const vk::StructureChain semaphore_chain = {
        vk::SemaphoreCreateInfo{},
        vk::SemaphoreTypeCreateInfo{
            .semaphoreType = vk::SemaphoreType::eTimeline,
            .initialValue = 0,
        },
    };
    auto [semaphore_result, sem] =
        instance.GetDevice().createSemaphoreUnique(semaphore_chain.get());
    ASSERT_MSG(semaphore_result == vk::Result::eSuccess, "Failed to create master semaphore: {}",
               vk::to_string(semaphore_result));
    semaphore = std::move(sem);
}

Semaphore::~Semaphore() = default;

void Semaphore::Refresh() {
    const SyncTimer timer{sync_stats_enabled, sync_stats.refresh_calls, sync_stats.refresh_ns};
    u64 this_tick{};
    u64 counter{};
    do {
        this_tick = gpu_tick.load(std::memory_order_acquire);
        auto [counter_result, cntr] = instance.GetDevice().getSemaphoreCounterValue(*semaphore);
        if (sync_stats_enabled) {
            sync_stats.counter_reads.fetch_add(1, std::memory_order_relaxed);
        }
        ASSERT_MSG(counter_result == vk::Result::eSuccess,
                   "Failed to get master semaphore value: {}", vk::to_string(counter_result));
        counter = cntr;
        if (optimize_refresh) {
            // A competing waiter can publish a newer value; retry publication, not the driver.
            while (this_tick < counter &&
                   !gpu_tick.compare_exchange_weak(this_tick, counter, std::memory_order_release,
                                                   std::memory_order_relaxed)) {
            }
            return;
        }
        if (counter < this_tick) {
            return;
        }
    } while (!gpu_tick.compare_exchange_weak(this_tick, counter, std::memory_order_release,
                                             std::memory_order_relaxed));
}

void Semaphore::Wait(u64 tick) {
    const SyncTimer timer{sync_stats_enabled, sync_stats.wait_calls, sync_stats.wait_ns};
    // No need to wait if the GPU is ahead of the tick
    if (IsFree(tick)) {
        return;
    }
    // Update the GPU tick and try again
    Refresh();
    if (IsFree(tick)) {
        return;
    }

    // inFAMOUS waits for the GPU several times a frame, for results the game reads right after
    // (see Rasterizer::FlushMirrors). The work waited for is tiny, but a blocking wait hands
    // the thread to the scheduler and comes back a good part of a millisecond late. So the
    // counter is polled for a short while first. I3_NO_SPIN_WAIT=1 switches this off.
    static const bool spin = Common::ElfInfo::Instance().GameSerial() == "CUSA00004" &&
                             std::getenv("I3_NO_SPIN_WAIT") == nullptr;
    if (spin) {
        const auto until = std::chrono::steady_clock::now() + std::chrono::microseconds(1500);
        do {
            for (int i = 0; i < 32; ++i) {
                _mm_pause();
            }
            Refresh();
            if (sync_stats_enabled) {
                sync_stats.spin_reads.fetch_add(1, std::memory_order_relaxed);
            }
            if (IsFree(tick)) {
                return;
            }
        } while (std::chrono::steady_clock::now() < until);
    }

    // If none of the above is hit, fallback to a regular wait
    const vk::SemaphoreWaitInfo wait_info = {
        .semaphoreCount = 1,
        .pSemaphores = &semaphore.get(),
        .pValues = &tick,
    };

    {
        const SyncTimer blocking_timer{sync_stats_enabled, sync_stats.blocking_calls,
                                       sync_stats.blocking_ns};
        while (instance.GetDevice().waitSemaphores(&wait_info, WAIT_TIMEOUT) !=
               vk::Result::eSuccess) {
        }
    }
    Refresh();
}

void Semaphore::ReportSyncStats() const {
    if (!sync_stats_enabled) {
        return;
    }
    const auto& s = sync_stats;
    LOG_INFO(Render_Vulkan,
             "GPU semaphore total: timeline {:#x} refresh_calls {} counter_reads {} refresh_ns {} "
             "wait_calls {} "
             "wait_ns {} spin_reads {} blocking_calls {} blocking_ns {}",
             std::bit_cast<u64>(Handle()), s.refresh_calls.load(), s.counter_reads.load(),
             s.refresh_ns.load(), s.wait_calls.load(), s.wait_ns.load(), s.spin_reads.load(),
             s.blocking_calls.load(), s.blocking_ns.load());
}

} // namespace Vulkan
