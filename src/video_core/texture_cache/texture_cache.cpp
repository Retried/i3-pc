// SPDX-FileCopyrightText: Copyright 2024-2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <array>
#include <atomic>
#include <fstream>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <xxhash.h>
#include "common/recording.h"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include "common/assert.h"
#include "common/debug.h"
#include "common/div_ceil.h"
#include "common/elf_info.h"
#include "common/hash.h"
#include "common/io_file.h"
#include "common/path_util.h"
#include "core/direct_aliases.h"
#include "core/emulator_settings.h"
#include "core/memory.h"
#include "video_core/buffer_cache/buffer_cache.h"
#include "video_core/page_manager.h"
#include "video_core/renderer_vulkan/liverpool_to_vk.h"
#include "video_core/renderer_vulkan/vk_instance.h"
#include "video_core/renderer_vulkan/vk_runtime.h"
#include "video_core/renderer_vulkan/vk_scheduler.h"
#include "video_core/texture_cache/host_compatibility.h"
#include "video_core/texture_cache/texture_cache.h"
#include "video_core/texture_cache/tile_manager.h"

namespace VideoCore {

static constexpr u32 MAX_IMAGES = std::numeric_limits<u16>::max();
static constexpr u32 MAX_IMAGE_VIEWS = std::numeric_limits<u16>::max();
static constexpr u32 MAX_SAMPLERS = std::numeric_limits<u16>::max();

TextureCache::TextureCache(const Vulkan::Instance& instance_, Vulkan::Scheduler& scheduler_,
                           Vulkan::Runtime& runtime_, AmdGpu::Liverpool* liverpool_,
                           BufferCache& buffer_cache_, PageManager& tracker_)
    : instance{instance_}, scheduler{scheduler_}, runtime{runtime_}, liverpool{liverpool_},
      buffer_cache{buffer_cache_}, tracker{tracker_}, slot_images{MAX_IMAGES},
      slot_image_views{MAX_IMAGE_VIEWS}, slot_samplers{MAX_SAMPLERS},
      blit_helper{instance, scheduler},
      tile_manager{instance, scheduler, runtime, buffer_cache.GetStreamBuffer()},
      readback_linear_images{EmulatorSettings.IsReadbackLinearImagesEnabled()} {

    const u32 max_samplers = std::min(instance.GetMaxSamplerAllocationCount(), MAX_SAMPLERS);
    trigger_gc_samplers = max_samplers * 3 / 4;
    pressure_gc_samplers = max_samplers * 7 / 8;
    critical_gc_samplers = max_samplers * 15 / 16;

    // Set up garbage collection parameters.
    if (!instance.CanReportMemoryUsage()) {
        trigger_gc_memory = 0;
        pressure_gc_memory = DEFAULT_PRESSURE_GC_MEMORY;
        critical_gc_memory = DEFAULT_CRITICAL_GC_MEMORY;
        return;
    }

    const s64 device_local_memory = static_cast<s64>(instance.GetTotalMemoryBudget());
    const s64 min_spacing_expected = device_local_memory - 1_GB;
    const s64 min_spacing_critical = device_local_memory - 512_MB;
    const s64 mem_threshold = std::min<s64>(device_local_memory, TARGET_GC_THRESHOLD);
    const s64 min_vacancy_expected = (6 * mem_threshold) / 10;
    const s64 min_vacancy_critical = (2 * mem_threshold) / 10;
    const s64 min_pressure_floor =
        std::clamp<s64>(device_local_memory / 4, 256_MB, DEFAULT_PRESSURE_GC_MEMORY);
    const s64 min_critical_floor =
        std::clamp<s64>(device_local_memory / 2, 512_MB, DEFAULT_CRITICAL_GC_MEMORY);
    pressure_gc_memory = static_cast<u64>(
        std::max<s64>(std::min(device_local_memory - min_vacancy_expected, min_spacing_expected),
                      min_pressure_floor));
    critical_gc_memory = static_cast<u64>(
        std::max<s64>(std::min(device_local_memory - min_vacancy_critical, min_spacing_critical),
                      min_critical_floor));
    trigger_gc_memory = static_cast<u64>((device_local_memory - mem_threshold) / 2);
}

TextureCache::~TextureCache() = default;

void TextureCache::ProcessDownloadImages() {
    std::unique_lock lk{download_images_mutex};
    for (const ImageId image_id : download_images) {
        DownloadImageMemory(image_id);
    }
    download_images.clear();
}

// Debug aid: SOTC_DUMP_AT=<seconds> writes every GPU-written image once, as raw texels with a
// small text header, to user/screenshots/dump for offline inspection.
void TextureCache::DebugDumpImages() {
    static const char* at = std::getenv("SOTC_DUMP_AT");
    static const auto start = std::chrono::steady_clock::now();
    static bool done = false;
    if (!at || done ||
        std::chrono::steady_clock::now() - start < std::chrono::seconds(std::atoi(at))) {
        return;
    }
    done = true;
    const auto dir = Common::FS::GetUserPath(Common::FS::PathType::ScreenshotsDir) / "dump";
    std::filesystem::create_directories(dir);
    u32 count = 0;
    for (u32 index = 0; index < 65536; ++index) {
        const ImageId image_id{index};
        if (!slot_images.IsAllocated(image_id)) {
            continue;
        }
        Image& image = slot_images[image_id];
        const auto& info = image.info;
        if (True(image.flags & ImageFlagBits::GpuModified) && info.size.width == 16 &&
            info.size.height == 16 && info.resources.layers > 1 && info.num_bits == 32) {
            // Small layered arrays (light probe inputs): all layers, tightly packed.
            const u32 layers = info.resources.layers;
            const u32 bytes = 16 * 16 * 4 * layers;
            const auto dl = runtime.GetStagingPool().Request(bytes, MemoryType::HostCached, 16);
            const vk::BufferImageCopy copy = {
                .bufferOffset = dl.offset,
                .bufferRowLength = 16,
                .bufferImageHeight = 16,
                .imageSubresource = {.aspectMask = vk::ImageAspectFlagBits::eColor,
                                     .mipLevel = 0,
                                     .baseArrayLayer = 0,
                                     .layerCount = layers},
                .imageOffset = {0, 0, 0},
                .imageExtent = {16, 16, 1},
            };
            runtime.DownloadImage(&image, dl.buffer, std::span{&copy, 1});
            scheduler.Finish();
            dl.Invalidate();
            Common::FS::IOFile out{dir / fmt::format("arr_{:x}_16x16x{}_{}.raw", info.guest_address,
                                                     layers, vk::to_string(info.pixel_format)),
                                   Common::FS::FileAccessMode::Create};
            out.WriteRaw<u8>(dl.mapped, bytes);
            continue;
        }
        if (False(image.flags & ImageFlagBits::GpuModified) || info.size.depth != 1 ||
            info.resources.layers != 1 || info.num_bits == 0 || info.size.width < 64 ||
            info.props.is_block || info.num_samples > 1 ||
            (info.props.is_depth && info.pixel_format != vk::Format::eD32Sfloat &&
             info.pixel_format != vk::Format::eD32SfloatS8Uint &&
             info.pixel_format != vk::Format::eD16Unorm) ||
            info.pitch < info.size.width) {
            continue;
        }
        // Oversized on purpose: the host format can be wider than the guest one.
        const u32 size = info.pitch * info.size.height * 16;
        const auto download = runtime.GetStagingPool().Request(size, MemoryType::HostCached, 16);
        const vk::BufferImageCopy copy = {
            .bufferOffset = download.offset,
            .bufferRowLength = info.pitch,
            .bufferImageHeight = info.size.height,
            .imageSubresource = {.aspectMask = info.props.is_depth
                                                   ? vk::ImageAspectFlagBits::eDepth
                                                   : vk::ImageAspectFlagBits::eColor,
                                 .mipLevel = 0,
                                 .baseArrayLayer = 0,
                                 .layerCount = 1},
            .imageOffset = {0, 0, 0},
            .imageExtent = {info.size.width, info.size.height, 1},
        };
        runtime.DownloadImage(&image, download.buffer, std::span{&copy, 1});
        scheduler.Finish();
        download.Invalidate();
        const auto name = fmt::format("{:03}_{:x}_{}x{}_p{}_b{}_{}", count++, info.guest_address,
                                      info.size.width, info.size.height, info.pitch, info.num_bits,
                                      vk::to_string(info.pixel_format));
        Common::FS::IOFile file{dir / (name + ".raw"), Common::FS::FileAccessMode::Create};
        const u32 texel_bytes = info.props.is_depth
                                    ? (info.pixel_format == vk::Format::eD16Unorm ? 2 : 4)
                                    : info.num_bits / 8;
        file.WriteRaw<u8>(download.mapped, info.pitch * info.size.height * texel_bytes);
    }
    LOG_ERROR(Render, "Dumped {} GPU images", count);
}

bool TextureCache::DownloadImageMemory(ImageId image_id) {
    Image& image = slot_images[image_id];
    const auto& info = image.info;
    auto* memory = Core::Memory::Instance();
    std::vector<u8> expected;
    Core::ReadbackMapping mapping;
    {
        std::scoped_lock lk{image.mutex};
        if (!image.CanBeDownloaded() || info.guest_size == 0 ||
            buffer_cache.IsRegionGpuModified(info.guest_address, info.guest_size)) {
            return false;
        }
        expected.resize(info.guest_size);
        mapping =
            memory->CaptureReadbackMapping(info.guest_address, info.guest_size, expected.data());
    }
    // Seed padding from guest memory. The tiler only overwrites real image texels.
    SmallVector<vk::BufferImageCopy, 14> copies;
    for (u32 mip = 0; mip < info.resources.levels; ++mip) {
        const auto& layout = info.mips_layout[mip];
        const u32 width = std::max(info.size.width >> mip, 1u);
        const u32 height = std::max(info.size.height >> mip, 1u);
        const u32 depth = info.props.is_volume ? std::max(info.size.depth >> mip, 1u) : 1u;
        const u64 block_width = info.props.is_block ? 4 : 1;
        const u64 row_bytes = Common::DivCeil<u64>(layout.pitch, block_width) * (info.num_bits / 8);
        const u64 rows = Common::DivCeil<u64>(layout.height, block_width);
        const u64 required = row_bytes * rows * depth * info.resources.layers;
        if (layout.pitch < width || layout.height < height ||
            u64(layout.offset) + layout.size > info.guest_size || required > layout.size ||
            layout.offset % (info.num_bits / 8) != 0) {
            return false;
        }
        copies.push_back(vk::BufferImageCopy{
            .bufferOffset = layout.offset,
            .bufferRowLength = layout.pitch,
            .bufferImageHeight = layout.height,
            .imageSubresource{.aspectMask = image.aspect_mask,
                              .mipLevel = mip,
                              .baseArrayLayer = 0,
                              .layerCount = info.resources.layers},
            .imageOffset = {0, 0, 0},
            .imageExtent = {width, height, depth},
        });
    }
    if (copies.empty()) {
        return false;
    }
    // A held allocation survives intermediate submits and callback processing during tiling.
    const auto download =
        runtime.GetStagingPool().Request(info.guest_size, MemoryType::HostCached, 256, true);
    std::memcpy(download.mapped, expected.data(), expected.size());
    download.Flush();
    tile_manager.TileImage(image, copies, download.buffer, download.offset, true);
    scheduler.Finish();
    download.Invalidate();
    const auto result =
        memory->WriteReadback(mapping, 0, download.mapped, info.guest_size, expected.data());
    runtime.GetStagingPool().FreeDeferred(download);
    buffer_cache.NotifyImageReadback(info.guest_address, info.guest_size);
    // The producer cannot advance until the CPU commit completes. No priority callback
    // can overwrite a later image/buffer owner or mutate the staging pool from another thread.
    return result.stale_bytes == 0 && result.conflict_bytes == 0;
}

void TextureCache::MarkAsMaybeDirty(ImageId image_id, Image& image) {
    if (image.hash == 0) {
        // Initialize hash
        image.hash = Core::Memory::Instance()->HashSparseMemory(image.info.guest_address,
                                                                image.info.guest_size);
    }
    image.flags |= ImageFlagBits::MaybeCpuDirty;
    UntrackImage(image_id);
}

void TextureCache::InvalidateMemory(VAddr addr, size_t size) {
    const auto pages_start = PageManager::GetPageAddr(addr);
    const auto pages_end = PageManager::GetNextPageAddr(addr + size - 1);

    SmallVector<ImageId, 8> image_ids;
    ForEachImageInRegion(pages_start, pages_end - pages_start,
                         [&](ImageId image_id, Image&) { image_ids.push_back(image_id); });

    for (const auto image_id : image_ids) {
        Image& image = slot_images[image_id];
        std::scoped_lock lk{image.mutex};

        const auto image_begin = image.info.guest_address;
        const auto image_end = image.info.guest_address + image.info.guest_size;
        if (image.Overlaps(addr, size)) {
            // Modified region overlaps image, so the image was definitely accessed by this fault.
            // Untrack the image, so that the range is unprotected and the guest can write freely.
            image.flags |= ImageFlagBits::CpuDirty;
            UntrackImage(image_id);
        } else if (pages_end < image_end) {
            // This page access may or may not modify the image.
            // We should not mark it as dirty now. If it really was modified
            // it will receive more invalidations on its other pages.
            // Remove tracking from this page only.
            UntrackImageHead(image_id);
        } else if (image_begin < pages_start) {
            // This page access does not modify the image but the page should be untracked.
            // We should not mark this image as dirty now. If it really was modified
            // it will receive more invalidations on its other pages.
            UntrackImageTail(image_id);
        } else {
            // Image begins and ends on this page so it can not receive any more invalidations.
            // We will check it's hash later to see if it really was modified.
            MarkAsMaybeDirty(image_id, image);
        }
    }
}

void TextureCache::InvalidateMemoryFromGPU(VAddr address, size_t max_size) {
    ForEachImageInRegion(address, max_size, [&](ImageId image_id, Image& image) {
        // Only consider images that match base address.
        // TODO: Maybe also consider subresources
        if (image.info.guest_address != address) {
            return;
        }
        // Ensure image is reuploaded when accessed again.
        image.flags |= ImageFlagBits::GpuDirty;
    });
}

void TextureCache::MarkAsMaybeGpuDirty(VAddr address, size_t size) {
    SmallVector<std::pair<VAddr, u64>, 4> ranges;
    ranges.emplace_back(address, size);
    Core::DirectAliases().ForEachAlias(address, size, [&](VAddr alias, u64 alias_size) {
        ranges.emplace_back(alias, alias_size);
    });
    for (const auto& [alias, alias_size] : ranges) {
        ForEachImageInRegion(alias, alias_size, [](ImageId, Image& image) {
            std::scoped_lock lk{image.mutex};
            image.flags |= ImageFlagBits::MaybeGpuDirty;
        });
    }
}

void TextureCache::UnmapMemory(VAddr cpu_addr, size_t size) {
    SmallVector<ImageId, 16> deleted_images;
    ForEachImageInRegion(cpu_addr, size, [&](ImageId id, Image&) { deleted_images.push_back(id); });
    for (const ImageId id : deleted_images) {
        // TODO: Download image data back to host.
        FreeImage(id);
    }
}

ImageId TextureCache::ResolveDepthOverlap(const ImageInfo& requested_info, BindingType binding,
                                          ImageId cache_image_id) {
    auto& cache_image = slot_images[cache_image_id];

    if (!cache_image.info.props.is_depth && !requested_info.props.is_depth) {
        return {};
    }

    const bool stencil_match =
        requested_info.props.has_stencil == cache_image.info.props.has_stencil;
    const bool bpp_match = requested_info.num_bits == cache_image.info.num_bits;

    // If an image in the cache has less slices we need to expand it
    bool recreate = cache_image.info.resources < requested_info.resources;

    switch (binding) {
    case BindingType::Texture:
        // The guest requires a depth sampled texture, but cache can offer only Rxf. Need to
        // recreate the image.
        recreate |= requested_info.props.is_depth && !cache_image.info.props.is_depth;
        break;
    case BindingType::Storage:
        // If the guest is going to use previously created depth as storage, the image needs to be
        // recreated. (TODO: Probably a case with linear rgba8 aliasing is legit)
        recreate |= cache_image.info.props.is_depth;
        break;
    case BindingType::RenderTarget:
        // Render target can have only Rxf format. If the cache contains only Dx[S8] we need to
        // re-create the image.
        ASSERT(!requested_info.props.is_depth);
        recreate |= cache_image.info.props.is_depth;
        break;
    case BindingType::DepthTarget:
        // The guest has requested previously allocated texture to be bound as a depth target.
        // In this case we need to convert Rx float to a Dx[S8] as requested
        recreate |= !cache_image.info.props.is_depth;

        // The guest is trying to bind a depth target and cache has it. Need to be sure that aspects
        // and bpp match
        recreate |= cache_image.info.props.is_depth && !(stencil_match && bpp_match);
        break;
    default:
        break;
    }

    if (recreate) {
        auto new_info = requested_info;
        new_info.resources = std::max(requested_info.resources, cache_image.info.resources);
        new_info.UpdateSize();
        // A surface the game uses as a depth target and as a plain float image in turn (a depth
        // buffer read by a compute pass) flips between the two kinds every frame. Creating and
        // destroying an image for each flip is slow, so the kind not in use is parked and taken
        // back on the next flip; only the contents are copied across.
        static const bool twins_enabled = std::getenv("SOTC_NO_TWINS") == nullptr;
        const bool format_flip = twins_enabled &&
                                 new_info.resources == cache_image.info.resources &&
                                 new_info.size == cache_image.info.size &&
                                 new_info.num_samples == cache_image.info.num_samples;
        ImageId new_image_id{};
        if (format_flip) {
            const auto twin = std::ranges::find_if(parked_twins, [&](ImageId id) {
                const ImageInfo& parked = slot_images[id].info;
                return parked.guest_address == new_info.guest_address &&
                       parked.pixel_format == new_info.pixel_format &&
                       parked.size == new_info.size && parked.resources == new_info.resources &&
                       parked.num_samples == new_info.num_samples;
            });
            if (twin != parked_twins.end()) {
                new_image_id = *twin;
                parked_twins.erase(twin);
            }
        }
        if (!new_image_id) {
            new_image_id = slot_images.Insert(instance, runtime, slot_image_views, new_info);
        }
        RegisterImage(new_image_id);

        // Inherit image usage
        auto& new_image = slot_images[new_image_id];
        new_image.usage = cache_image.usage;
        if (new_info.num_samples == 1 &&
            (new_info.resources.layers > cache_image.info.resources.layers ||
             new_info.resources.levels > cache_image.info.resources.levels)) {
            RefreshImage(new_image);
        }
        new_image.flags &= ~ImageFlagBits::Dirty;
        // When creating a depth buffer through overlap resolution don't clear it on first use.
        new_image.info.meta_info.htile_clear_mask = 0;
        runtime.CopyColorAndDepth(&cache_image, &new_image);

        if (format_flip) {
            // Park the old kind instead of destroying it.
            {
                std::scoped_lock lk{slot_images[cache_image_id].mutex};
                UntrackImage(cache_image_id);
            }
            UnregisterImage(cache_image_id);
            parked_twins.push_back(cache_image_id);
            if (parked_twins.size() > 8) {
                DeleteImage(parked_twins.front());
                parked_twins.erase(parked_twins.begin());
            }
        } else {
            // Free the cache image.
            FreeImage(cache_image_id);
        }
        return new_image_id;
    }

    // Will be handled by view
    return cache_image_id;
}

std::tuple<ImageId, int, int> TextureCache::ResolveOverlap(const ImageInfo& image_info,
                                                           BindingType binding,
                                                           ImageId cache_image_id,
                                                           ImageId merged_image_id) {
    static constexpr u64 NUM_FRAMES_BEFORE_REMOVAL = 32;

    auto& cache_image = slot_images[cache_image_id];
    const bool safe_to_delete =
        scheduler.CurrentTick() - cache_image.tick_accessed_last > NUM_FRAMES_BEFORE_REMOVAL;

    // Equal address
    if (image_info.guest_address == cache_image.info.guest_address) {
        const u32 lhs_block_size = image_info.num_bits * image_info.num_samples;
        const u32 rhs_block_size = cache_image.info.num_bits * cache_image.info.num_samples;
        if (image_info.BlockDim() != cache_image.info.BlockDim() ||
            lhs_block_size != rhs_block_size) {
            // Very likely this kind of overlap is caused by allocation from a pool.
            if (safe_to_delete) {
                FreeImage(cache_image_id);
            }
            return {merged_image_id, -1, -1};
        }

        if (const auto depth_image_id = ResolveDepthOverlap(image_info, binding, cache_image_id)) {
            return {depth_image_id, -1, -1};
        }

        // Compressed view of uncompressed image with same block size.
        if (image_info.props.is_block && !cache_image.info.props.is_block) {
            return {ExpandImage(image_info, cache_image_id), -1, -1};
        }

        if (image_info.guest_size == cache_image.info.guest_size &&
            (image_info.type == AmdGpu::ImageType::Color3D ||
             cache_image.info.type == AmdGpu::ImageType::Color3D)) {
            return {ExpandImage(image_info, cache_image_id), -1, -1};
        }

        const bool pow2_padding_only =
            image_info.props.is_pow2 != cache_image.info.props.is_pow2 &&
            image_info.tile_mode == cache_image.info.tile_mode &&
            image_info.size == cache_image.info.size &&
            image_info.pitch == cache_image.info.pitch && image_info.resources.levels == 1 &&
            cache_image.info.resources.levels == 1 && image_info.resources.layers == 1 &&
            cache_image.info.resources.layers == 1;

        // Size and resources are less than or equal, use image view.
        if (image_info.pixel_format != cache_image.info.pixel_format ||
            image_info.guest_size <= cache_image.info.guest_size || pow2_padding_only) {
            auto result_id = merged_image_id ? merged_image_id : cache_image_id;
            const auto& result_image = slot_images[result_id];
            const bool is_compatible =
                IsVulkanFormatCompatible(result_image.info.pixel_format, image_info.pixel_format);
            return {is_compatible ? result_id : ImageId{}, -1, -1};
        }

        // Size and resources are greater, expand the image.
        if (image_info.type == cache_image.info.type &&
            image_info.resources > cache_image.info.resources) {
            return {ExpandImage(image_info, cache_image_id), -1, -1};
        }

        // Size is greater but resources are not, because the tiling mode is different.
        // Likely the address is reused for a image with a different tiling mode.
        // Same surface described once with the base and once with the alternate (Neo) tiling:
        // render targets are never detiled from guest memory, so both name the same image.
        if (image_info.alt_tile != cache_image.info.alt_tile &&
            image_info.tile_mode == cache_image.info.tile_mode &&
            image_info.size == cache_image.info.size &&
            image_info.pixel_format == cache_image.info.pixel_format) {
            return {merged_image_id ? merged_image_id : cache_image_id, -1, -1};
        }

        if (image_info.tile_mode != cache_image.info.tile_mode) {
            if (safe_to_delete) {
                FreeImage(cache_image_id);
            }
            return {merged_image_id, -1, -1};
        }

        // Enhanced debug logging for unreachable case
        // Calculate expected size based on format and dimensions
        u64 expected_size =
            (static_cast<u64>(image_info.size.width) * static_cast<u64>(image_info.size.height) *
             static_cast<u64>(image_info.size.depth) * static_cast<u64>(image_info.num_bits) / 8);
        LOG_ERROR(Render_Vulkan,
                  "Unresolvable image overlap with equal memory address:\n"
                  "=== OLD IMAGE (cached) ===\n"
                  "  Address:        {:#x}\n"
                  "  Size:           {:#x} bytes\n"
                  "  Format:         {}\n"
                  "  Type:           {}\n"
                  "  Width:          {}\n"
                  "  Height:         {}\n"
                  "  Depth:          {}\n"
                  "  Pitch:          {}\n"
                  "  Mip levels:     {}\n"
                  "  Array layers:   {}\n"
                  "  Samples:        {}\n"
                  "  Tile mode:      {:#x}\n"
                  "  Block size:     {} bits\n"
                  "  Is block-comp:  {}\n"
                  "  Guest size:     {:#x}\n"
                  "  Last accessed:  tick {}\n"
                  "  Safe to delete: {}\n"
                  "  isPow2:         {}\n"
                  "  Alt tile:       {}\n"
                  "\n"
                  "=== NEW IMAGE (requested) ===\n"
                  "  Address:        {:#x}\n"
                  "  Size:           {:#x} bytes\n"
                  "  Format:         {}\n"
                  "  Type:           {}\n"
                  "  Width:          {}\n"
                  "  Height:         {}\n"
                  "  Depth:          {}\n"
                  "  Pitch:          {}\n"
                  "  Mip levels:     {}\n"
                  "  Array layers:   {}\n"
                  "  Samples:        {}\n"
                  "  Tile mode:      {:#x}\n"
                  "  Block size:     {} bits\n"
                  "  Is block-comp:  {}\n"
                  "  Guest size:     {:#x}\n"
                  "  isPow2:         {}\n"
                  "  Alt tile:       {}\n"
                  "\n"
                  "=== COMPARISON ===\n"
                  "  Same format:           {}\n"
                  "  Same type:             {}\n"
                  "  Same tile mode:        {}\n"
                  "  Same block size:       {}\n"
                  "  Same BlockDim:         {}\n"
                  "  Same pitch:            {}\n"
                  "  Same pow2:             {}\n"
                  "  Same alt tile:         {}\n"
                  "  Old resources <= new:  {} (old: {}, new: {})\n"
                  "  Old size <= new size:  {}\n"
                  "  Expected size (calc):  {} bytes\n"
                  "  Size ratio (new/expected): {:.2f}x\n"
                  "  Size ratio (new/old):  {:.2f}x\n"
                  "  Old vs expected diff:  {} bytes ({:+.2f}%)\n"
                  "  New vs expected diff:  {} bytes ({:+.2f}%)\n"
                  "  Merged image ID:       {}\n"
                  "  Binding type:          {}\n"
                  "  Current tick:          {}\n"
                  "  Age (ticks since last access): {}",

                  // Old image details
                  cache_image.info.guest_address, cache_image.info.guest_size,
                  vk::to_string(cache_image.info.pixel_format),
                  static_cast<int>(cache_image.info.type), cache_image.info.size.width,
                  cache_image.info.size.height, cache_image.info.size.depth, cache_image.info.pitch,
                  cache_image.info.resources.levels, cache_image.info.resources.layers,
                  cache_image.info.num_samples, static_cast<u32>(cache_image.info.tile_mode),
                  cache_image.info.num_bits, +cache_image.info.props.is_block,
                  cache_image.info.guest_size, cache_image.tick_accessed_last, safe_to_delete,
                  bool(cache_image.info.props.is_pow2), cache_image.info.alt_tile,

                  // New image details
                  image_info.guest_address, image_info.guest_size,
                  vk::to_string(image_info.pixel_format), static_cast<int>(image_info.type),
                  image_info.size.width, image_info.size.height, image_info.size.depth,
                  image_info.pitch, image_info.resources.levels, image_info.resources.layers,
                  image_info.num_samples, static_cast<u32>(image_info.tile_mode),
                  image_info.num_bits, image_info.props.is_block, image_info.guest_size,
                  bool(image_info.props.is_pow2), image_info.alt_tile,

                  // Comparison
                  (image_info.pixel_format == cache_image.info.pixel_format),
                  (image_info.type == cache_image.info.type),
                  (image_info.tile_mode == cache_image.info.tile_mode),
                  (image_info.num_bits == cache_image.info.num_bits),
                  (image_info.BlockDim() == cache_image.info.BlockDim()),
                  (image_info.pitch == cache_image.info.pitch),
                  (image_info.props.is_pow2 == cache_image.info.props.is_pow2),
                  (image_info.alt_tile == cache_image.info.alt_tile),
                  (cache_image.info.resources <= image_info.resources),
                  cache_image.info.resources.levels, image_info.resources.levels,
                  (cache_image.info.guest_size <= image_info.guest_size), expected_size,

                  // Size ratios
                  static_cast<double>(image_info.guest_size) / expected_size,
                  static_cast<double>(image_info.guest_size) / cache_image.info.guest_size,

                  // Difference between actual and expected sizes with percentages
                  static_cast<s64>(cache_image.info.guest_size) - static_cast<s64>(expected_size),
                  (static_cast<double>(cache_image.info.guest_size) / expected_size - 1.0) * 100.0,

                  static_cast<s64>(image_info.guest_size) - static_cast<s64>(expected_size),
                  (static_cast<double>(image_info.guest_size) / expected_size - 1.0) * 100.0,

                  merged_image_id.index, static_cast<int>(binding), scheduler.CurrentTick(),
                  scheduler.CurrentTick() - cache_image.tick_accessed_last);

        UNREACHABLE_MSG("Encountered unresolvable image overlap with equal memory address.");
    }

    // Right overlap, the image requested is a possible subresource of the image from cache.
    if (image_info.guest_address > cache_image.info.guest_address) {
        if (auto mip = image_info.MipOf(cache_image.info); mip >= 0) {
            if (auto slice = image_info.SliceOf(cache_image.info, mip); slice >= 0) {
                return {cache_image_id, mip, slice};
            }
        }

        // Image isn't a subresource but a chance overlap.
        if (safe_to_delete) {
            FreeImage(cache_image_id);
        }

        return {{}, -1, -1};
    } else {
        // Left overlap, the image from cache is a possible subresource of the image requested
        if (auto mip = cache_image.info.MipOf(image_info); mip >= 0) {
            if (auto slice = cache_image.info.SliceOf(image_info, mip); slice >= 0) {
                // We have a larger image created and a separate one, representing a subres of it
                // bound as render target. In this case we need to rebind render target.
                if (cache_image.binding.is_target) {
                    cache_image.binding.needs_rebind = 1u;
                    if (merged_image_id) {
                        GetImage(merged_image_id).binding.is_target = 1u;
                    }

                    FreeImage(cache_image_id);
                    return {merged_image_id, -1, -1};
                }

                // We need to have a larger, already allocated image to copy this one into
                if (merged_image_id) {
                    auto& merged_image = slot_images[merged_image_id];
                    runtime.CopyMip(&cache_image, &merged_image, mip, slice);
                    FreeImage(cache_image_id);
                }
            }
        }
    }

    return {merged_image_id, -1, -1};
}

ImageId TextureCache::ExpandImage(const ImageInfo& info, ImageId image_id) {
    const auto new_image_id = slot_images.Insert(instance, runtime, slot_image_views, info);
    RegisterImage(new_image_id);

    auto& src_image = slot_images[image_id];
    auto& new_image = slot_images[new_image_id];

    RefreshImage(new_image);
    runtime.CopyImage(&src_image, &new_image);

    if (src_image.binding.is_bound || src_image.binding.is_target) {
        src_image.binding.needs_rebind = 1u;
    }

    new_image.flags &= ~ImageFlagBits::Dirty;
    new_image.flags |=
        src_image.flags & (ImageFlagBits::GpuModified | ImageFlagBits::MaybeGpuDirty);
    FreeImage(image_id);
    TrackImage(new_image_id);
    return new_image_id;
}

ImageId TextureCache::FindImage(ImageDesc& desc, bool exact_fmt) {
    const auto& info = desc.info;
    ASSERT(info.guest_address != 0);
    {
        // Temporary: SOTC_FINDLOG=1 lists every description of 16x16 layered images.
        static const bool on = std::getenv("SOTC_FINDLOG") != nullptr;
        static std::unordered_set<u64> seen;
        if (on && info.size.width == 16 && info.size.height == 16 &&
            seen.insert(info.guest_address ^ (u64(info.guest_size) << 36) ^ (u64(desc.type) << 60) ^
                        (u64(info.pixel_format) << 8) ^
                        (u64(desc.view_info.range.base.layer) << 24) ^
                        (u64(desc.view_info.range.extent.layers) << 50))
                .second) {
            LOG_ERROR(Render,
                      "findlog addr {:#x} size {:#x} layers {} fmt {} binding {} "
                      "viewlayer {} n {} type {}",
                      info.guest_address, info.guest_size, info.resources.layers,
                      vk::to_string(info.pixel_format), u32(desc.type),
                      desc.view_info.range.base.layer, desc.view_info.range.extent.layers,
                      u32(desc.view_info.type));
        }
    }

    // I3_NO_FIND_MEMO=1 turns the lookup memo off (A/B measurement).
    static const bool memo = std::getenv("I3_NO_FIND_MEMO") == nullptr;
    FoundImage& found = found_images[((info.guest_address >> 12) ^ (info.guest_address >> 23) ^
                                      info.guest_size ^ (u64(info.pixel_format) << 3)) &
                                     (found_images.size() - 1)];
    if (memo && found.generation == image_set_generation &&
        found.guest_address == info.guest_address && found.guest_size == info.guest_size &&
        found.size == info.size && found.pixel_format == info.pixel_format &&
        found.type == info.type && found.exact_fmt == exact_fmt) {
        Image& image = slot_images[found.image_id];
        image.tick_accessed_last = scheduler.CurrentTick();
        TouchImage(image);
        return found.image_id;
    }

    SmallVector<ImageId, 8> image_ids;
    ForEachImageInRegion(info.guest_address, info.guest_size,
                         [&](ImageId image_id, Image& image) { image_ids.push_back(image_id); });

    ImageId image_id{};
    bool perfect_match = false;

    // Check for a perfect match first
    for (const auto& cache_id : image_ids) {
        auto& cache_image = slot_images[cache_id];
        if (cache_image.info.guest_address != info.guest_address) {
            continue;
        }
        if (cache_image.info.guest_size != info.guest_size) {
            continue;
        }
        if (cache_image.info.size != info.size) {
            continue;
        }
        if (!IsVulkanFormatCompatible(cache_image.info.pixel_format, info.pixel_format) ||
            (cache_image.info.type != info.type && info.size != Extent3D{1, 1, 1})) {
            continue;
        }
        if (exact_fmt && info.pixel_format != cache_image.info.pixel_format) {
            continue;
        }
        image_id = cache_id;
        perfect_match = true;
    }

    // Try to resolve overlaps (if any)
    int view_mip{-1};
    int view_slice{-1};
    if (!image_id) {
        for (const auto& cache_id : image_ids) {
            view_mip = -1;
            view_slice = -1;

            const auto& merged_info = image_id ? slot_images[image_id].info : info;
            auto [overlap_image_id, overlap_view_mip, overlap_view_slice] =
                ResolveOverlap(merged_info, desc.type, cache_id, image_id);
            if (overlap_image_id) {
                image_id = overlap_image_id;
                view_mip = overlap_view_mip;
                view_slice = overlap_view_slice;
            }
        }
    }

    if (image_id) {
        Image& image_resolved = slot_images[image_id];
        if (exact_fmt && info.pixel_format != image_resolved.info.pixel_format) {
            // Cannot reuse this image as we need the exact requested format.
            image_id = {};
        } else if (image_resolved.info.resources < info.resources) {
            // The image was clearly picked up wrong.
            FreeImage(image_id);
            image_id = {};
            LOG_WARNING(Render_Vulkan, "Image overlap resolve failed");
        }
    }
    // Create and register a new image
    if (!image_id) {
        image_id = slot_images.Insert(instance, runtime, slot_image_views, info);
        RegisterImage(image_id);
    }

    Image& image = slot_images[image_id];
    image.tick_accessed_last = scheduler.CurrentTick();
    TouchImage(image);

    // Only exact matches are remembered: anything resolved through an overlap, or created
    // just now (which changed the generation), goes through the full path again.
    if (memo && perfect_match && slot_images[image_id].info.guest_address == info.guest_address) {
        found = {image_set_generation, info.guest_address, info.guest_size, info.size,
                 info.pixel_format,    info.type,          exact_fmt,       image_id};
    }

    // If the image requested is a subresource of the image from cache record its location.
    if (view_mip > 0) {
        desc.view_info.range.base.level = view_mip;
    }
    if (view_slice > 0) {
        desc.view_info.range.base.layer = view_slice;
    }

    return image_id;
}

ImageId TextureCache::FindImageFromRange(VAddr address, size_t size, bool ensure_valid) {
    SmallVector<ImageId, 4> image_ids;
    ForEachImageWithAddress(address, [&](ImageId image_id, Image& image) {
        if (ensure_valid && !image.SafeToDownload()) {
            return;
        }
        image_ids.push_back(image_id);
    });
    if (image_ids.size() == 1) {
        // Sometimes image size might not exactly match with requested buffer size
        // If we only found 1 candidate image use it without too many questions.
        return image_ids.back();
    }
    if (!image_ids.empty()) {
        for (s32 i = 0; i < image_ids.size(); ++i) {
            Image& image = slot_images[image_ids[i]];
            if (image.info.guest_size == size) {
                return image_ids[i];
            }
        }
        LOG_WARNING(Render_Vulkan,
                    "Failed to find exact image match for copy addr={:#x}, size={:#x}", address,
                    size);
    }
    return {};
}

ImageView& TextureCache::FindTexture(ImageId image_id, const ImageDesc& desc) {
    Image& image = slot_images[image_id];
    if (desc.type == BindingType::Storage) {
        image.flags |= ImageFlagBits::GpuModified;
        if (readback_linear_images && (!image.info.props.is_tiled || image.info.size.width <= 8) &&
            image.info.guest_address != 0) {
            std::unique_lock lk{download_images_mutex};
            download_images.emplace(image_id);
        }
    }
    UpdateImage(image_id);
    return image.FindView(desc.view_info);
}

void TextureCache::RegisterMeta(VAddr address, MetaDataInfo info) {
    const auto [it, inserted] = surface_metas.try_emplace(address, info);
    if (inserted) {
        return;
    }
    auto& registered = it->second;
    if (registered.type != info.type || registered.owner_id != info.owner_id ||
        registered.owner_uid != info.owner_uid) {
        registered = info;
        return;
    }
    // Rebinding the same owner must not restore a consumed fast clear.
    registered.num_samples = info.num_samples;
}

void TextureCache::UnregisterMeta(VAddr address, u64 owner_uid) {
    const auto it = surface_metas.find(address);
    if (it != surface_metas.end() && it->second.owner_uid == owner_uid) {
        surface_metas.erase(it);
    }
}

ImageView& TextureCache::FindRenderTarget(ImageId image_id, const ImageDesc& desc) {
    Image& image = slot_images[image_id];
    image.flags |= ImageFlagBits::GpuModified;
    if (readback_linear_images && (!image.info.props.is_tiled || image.info.size.width <= 8)) {
        std::unique_lock lk{download_images_mutex};
        download_images.emplace(image_id);
    }
    image.usage.render_target = 1u;
    UpdateImage(image_id);

    // Register meta data for this color buffer
    const VAddr cmask_addr = desc.info.meta_info.cmask_addr;
    if (image.info.meta_info.cmask_addr != cmask_addr) {
        UnregisterMeta(image.info.meta_info.cmask_addr, image.image_uid);
        image.info.meta_info.cmask_addr = cmask_addr;
    }
    if (cmask_addr) {
        RegisterMeta(cmask_addr, MetaDataInfo{.type = MetaType::CMask,
                                              .owner_id = image_id,
                                              .owner_uid = image.image_uid,
                                              .num_samples = image.info.num_samples});
    }

    const VAddr fmask_addr = desc.info.meta_info.fmask_addr;
    if (image.info.meta_info.fmask_addr != fmask_addr) {
        UnregisterMeta(image.info.meta_info.fmask_addr, image.image_uid);
        image.info.meta_info.fmask_addr = fmask_addr;
    }
    if (fmask_addr) {
        RegisterMeta(fmask_addr, MetaDataInfo{.type = MetaType::FMask,
                                              .owner_id = image_id,
                                              .owner_uid = image.image_uid,
                                              .num_samples = image.info.num_samples});
    }

    return image.FindView(desc.view_info, false);
}

ImageView& TextureCache::FindDepthTarget(ImageId image_id, const ImageDesc& desc) {
    Image& image = slot_images[image_id];
    image.flags |= ImageFlagBits::GpuModified;
    image.usage.depth_target = 1u;
    UpdateImage(image_id);

    // Register meta data for this depth buffer
    const VAddr htile_addr = desc.info.meta_info.htile_addr;
    if (image.info.meta_info.htile_addr != htile_addr) {
        UnregisterMeta(image.info.meta_info.htile_addr, image.image_uid);
        image.info.meta_info.htile_addr = htile_addr;
    }
    if (htile_addr) {
        RegisterMeta(htile_addr, MetaDataInfo{.type = MetaType::HTile,
                                              .owner_id = image_id,
                                              .owner_uid = image.image_uid,
                                              .num_samples = image.info.num_samples,
                                              .clear_mask = image.info.meta_info.htile_clear_mask});
    }

    AssociateStencil(image_id, desc.info);

    return image.FindView(desc.view_info, false);
}

void TextureCache::AssociateStencil(ImageId depth_id, const ImageInfo& depth_info) {
    if (depth_info.stencil_addr == 0) {
        return;
    }
    ImageId stencil_id{};
    ForEachImageInRegion(
        depth_info.stencil_addr, depth_info.stencil_size, [&](ImageId image_id, Image& image) {
            if (image.info.guest_address != depth_info.stencil_addr) {
                return;
            }
            if (image.info.pixel_format == vk::Format::eUndefined ||
                Vulkan::LiverpoolToVK::IsFormatStencilCompatible(image.info.pixel_format)) {
                stencil_id = image_id;
            }
        });
    if (!stencil_id) {
        ImageInfo info{};
        info.guest_address = depth_info.stencil_addr;
        info.guest_size = depth_info.stencil_size;
        info.size = depth_info.size;
        stencil_id = slot_images.Insert(instance, runtime, slot_image_views, info);
        RegisterImage(stencil_id);
    }
    Image& stencil_image = slot_images[stencil_id];
    TouchImage(stencil_image);
    stencil_image.AssociateDepth(depth_id, slot_images[depth_id].image_uid);
}

void TextureCache::RefreshImage(Image& image) {
    if (False(image.flags & ImageFlagBits::Dirty) || image.info.num_samples > 1) {
        return;
    }
    Common::FreezeTimer freeze_timer{1};

    RENDERER_TRACE;
    TRACE_HINT(fmt::format("{:x}:{:x}", image.info.guest_address, image.info.guest_size));

    if (True(image.flags & ImageFlagBits::MaybeCpuDirty) &&
        False(image.flags & ImageFlagBits::CpuDirty)) {
        const u64 hash = Core::Memory::Instance()->HashSparseMemory(image.info.guest_address,
                                                                    image.info.guest_size);
        if (image.hash == hash) {
            image.flags &= ~ImageFlagBits::MaybeCpuDirty;
            return;
        }
        image.hash = hash;
    }

    const u32 num_layers = image.info.resources.layers;
    const u32 num_mips = image.info.resources.levels;
    const bool is_gpu_modified = True(image.flags & ImageFlagBits::GpuModified);
    const bool is_gpu_dirty = True(image.flags & ImageFlagBits::GpuDirty);

    SmallVector<vk::BufferImageCopy, 14> image_copies;
    for (u32 m = 0; m < num_mips; m++) {
        const u32 width = std::max(image.info.size.width >> m, 1u);
        const u32 height = std::max(image.info.size.height >> m, 1u);
        const u32 depth =
            image.info.props.is_volume ? std::max(image.info.size.depth >> m, 1u) : 1u;
        const auto [mip_size, mip_pitch, mip_height, mip_offset] = image.info.mips_layout[m];
        const u32 extent_width = mip_pitch ? std::min<u32>(mip_pitch, width) : width;
        const u32 extent_height = mip_height ? std::min<u32>(mip_height, height) : height;
        image_copies.push_back({
            .bufferOffset = mip_offset,
            .bufferRowLength = mip_pitch,
            .bufferImageHeight = mip_height,
            .imageSubresource{
                .aspectMask = image.aspect_mask & ~vk::ImageAspectFlagBits::eStencil,
                .mipLevel = m,
                .baseArrayLayer = 0,
                .layerCount = num_layers,
            },
            .imageOffset = {0, 0, 0},
            .imageExtent = {extent_width, extent_height, depth},
        });
    }

    if (image_copies.empty()) {
        image.flags &= ~ImageFlagBits::Dirty;
        return;
    }

    scheduler.EndRendering();

    const auto [in_buffer, in_offset] =
        buffer_cache.ObtainBufferForImage(image.info.guest_address, image.info.guest_size);
    const auto [buffer, offset] = tile_manager.DetileImage(in_buffer, in_offset, image.info);
    for (auto& copy : image_copies) {
        copy.bufferOffset += offset;
    }

    runtime.UploadImage(&image, buffer, image_copies);
    {
        // A guest write that faulted while the data above was being read has untracked the
        // image and set its dirty flag, which the upload then cleared with the rest. Nothing
        // would fault again, and the image would keep the half-written data it just received
        // (seen with textures that are still being streamed in). Keep it dirty instead.
        std::scoped_lock lk{image.mutex};
        if (True(image.flags & ImageFlagBits::Registered) &&
            (image.track_addr != image.info.guest_address ||
             image.track_addr_end != image.info.guest_address + image.info.guest_size)) {
            image.flags |= ImageFlagBits::CpuDirty;
        }
    }
    ApplyTexturePack(image);
}

std::atomic<PromptSet> g_prompt_set{PromptSet::PlayStation};
std::atomic<bool> g_pack_reload{false};
static std::atomic<bool> g_pack_files_stale{false};

namespace {
constexpr std::array<const char*, 4> PromptStyleKeys{"auto", "playstation", "xbox", "keyboard"};

std::atomic<PromptStyle>& StoredPromptStyle() {
    // Retain the existing force.txt values; missing or unknown values select Auto.
    static std::atomic<PromptStyle> style{[] {
        const auto path =
            Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "sotc_textures" / "force.txt";
        std::ifstream file{path};
        std::string word;
        file >> word;
        for (size_t i = 0; i < PromptStyleKeys.size(); ++i) {
            if (word == PromptStyleKeys[i]) {
                return static_cast<PromptStyle>(i);
            }
        }
        return PromptStyle::Auto;
    }()};
    return style;
}
} // namespace

PromptStyle GetPromptStyle() {
    return StoredPromptStyle().load(std::memory_order_relaxed);
}

bool SetPromptStyle(PromptStyle style) {
    if (size_t(style) >= PromptStyleKeys.size()) {
        return false;
    }
    const auto dir = Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "sotc_textures";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    if (ec) {
        return false;
    }
    std::ofstream file{dir / "force.txt"};
    file << PromptStyleKeys[size_t(style)] << '\n';
    file.close();
    if (!file) {
        return false;
    }
    StoredPromptStyle().store(style, std::memory_order_relaxed);
    return true;
}

PromptSet ActivePromptSet() {
    switch (GetPromptStyle()) {
    case PromptStyle::PlayStation:
        return PromptSet::PlayStation;
    case PromptStyle::Xbox:
        return PromptSet::Xbox;
    case PromptStyle::Keyboard:
        return PromptSet::Keyboard;
    default:
        return g_prompt_set.load(std::memory_order_relaxed);
    }
}

void TextureCache::ApplyTexturePack(Image& image) {
    static const bool enabled = Common::ElfInfo::Instance().GameSerial() == "CUSA00004";
    if (!enabled) {
        return;
    }
    // File name: <hash of the guest data, 16 hex digits>.bin, holding the mip chain as
    // consecutive untiled levels in the image's own format.
    static const auto dir =
        Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "sotc_textures";
    static const bool dumping = std::getenv("SOTC_TEXDUMP") != nullptr;
    static const bool dump_unknown = std::getenv("SOTC_DUMP_UNKNOWN_GLYPHS") != nullptr;
    // One set of replacements per prompt style (see PromptSet): <dir>/keyboard and <dir>/xbox.
    // Loose files in <dir> itself count as keyboard glyphs. PlayStation prompts are the
    // game's own textures, so that set stays empty.
    struct PackTexture {
        std::vector<u8> data;
        std::vector<vk::BufferImageCopy> regions;
    };
    using PackFiles = std::unordered_map<u64, PackTexture>;
    const auto load_packs = [] {
        std::array<PackFiles, 3> sets;
        const auto load = [](const std::filesystem::path& from, PackFiles& files) {
            std::error_code ec;
            for (const auto& entry : std::filesystem::directory_iterator(from, ec)) {
                const auto path = entry.path();
                const bool patch = path.extension() == ".patch";
                if (path.extension() != ".bin" && !patch) {
                    continue;
                }
                const std::string stem = path.stem().string();
                if (stem.size() != 16 ||
                    stem.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos) {
                    continue;
                }
                Common::FS::IOFile file{path, Common::FS::FileAccessMode::Read};
                if (!file.IsOpen() || file.GetSize() == 0 || file.GetSize() > 8_MB) {
                    continue;
                }
                std::vector<u8> data(file.GetSize());
                if (file.ReadRaw<u8>(data.data(), data.size()) != data.size()) {
                    continue;
                }
                PackTexture texture;
                if (!patch) {
                    texture.data = std::move(data);
                } else {
                    // Sparse RGBA atlas patches retain all unsupported guest artwork.
                    // I3P1, width, height, count; then x/y/w/h and bottom-up RGBA per region.
                    if (stem != "7824aa19ec8ef328" || data.size() < 16 ||
                        std::memcmp(data.data(), "I3P1", 4) != 0) {
                        continue;
                    }
                    const auto word = [&](size_t at) {
                        return u32(data[at]) | (u32(data[at + 1]) << 8) |
                               (u32(data[at + 2]) << 16) | (u32(data[at + 3]) << 24);
                    };
                    const u32 count = word(12);
                    if (word(4) != 512 || word(8) != 512 || count == 0 || count > 64) {
                        continue;
                    }
                    size_t cursor = 16;
                    for (u32 i = 0; i < count && cursor + 16 <= data.size(); ++i) {
                        const u32 x = word(cursor), y = word(cursor + 4);
                        const u32 w = word(cursor + 8), h = word(cursor + 12);
                        cursor += 16;
                        if (!w || !h || w > 512 || h > 512 || x > 512 - w || y > 512 - h ||
                            cursor + u64(w) * h * 4 > data.size()) {
                            break;
                        }
                        texture.regions.push_back(vk::BufferImageCopy{
                            .bufferOffset = texture.data.size(),
                            .imageSubresource = {.aspectMask = vk::ImageAspectFlagBits::eColor,
                                                 .mipLevel = 0,
                                                 .baseArrayLayer = 0,
                                                 .layerCount = 1},
                            .imageOffset = {s32(x), s32(y), 0},
                            .imageExtent = {w, h, 1},
                        });
                        const size_t bytes = size_t(w) * h * 4;
                        texture.data.insert(texture.data.end(), data.begin() + cursor,
                                            data.begin() + cursor + bytes);
                        cursor += bytes;
                    }
                    if (texture.regions.size() != count || cursor != data.size()) {
                        LOG_WARNING(Render, "Ignoring invalid prompt patch {}", path.string());
                        continue;
                    }
                }
                const u64 hash = std::strtoull(stem.c_str(), nullptr, 16);
                if (patch) {
                    files.insert_or_assign(hash, std::move(texture));
                } else {
                    files.emplace(hash, std::move(texture));
                }
            }
        };
        load(dir, sets[size_t(PromptSet::Keyboard)]);
        load(dir / "keyboard", sets[size_t(PromptSet::Keyboard)]);
        load(dir / "xbox", sets[size_t(PromptSet::Xbox)]);
        LOG_INFO(Render, "Texture pack: {} keyboard and {} Xbox replacement textures",
                 sets[size_t(PromptSet::Keyboard)].size(), sets[size_t(PromptSet::Xbox)].size());
        return sets;
    };
    static auto packs = load_packs();
    if (g_pack_files_stale.exchange(false)) {
        packs = load_packs();
    }
    const bool pack_empty = std::ranges::all_of(packs, &PackFiles::empty);
    const auto& info = image.info;
    if ((pack_empty && !dumping) || info.size.width > 2048 || info.size.height > 2048 ||
        info.size.depth != 1 || info.resources.layers != 1 || info.num_samples > 1 ||
        info.props.is_depth || info.num_bits == 0 || info.guest_size > 8_MB ||
        True(image.flags & ImageFlagBits::GpuModified)) {
        return;
    }
    auto* memory = Core::Memory::Instance();
    if (!memory->IsValidMapping(info.guest_address, info.guest_size)) {
        return;
    }
    const u64 hash = memory->HashSparseMemory(info.guest_address, info.guest_size);
    const auto level_size = [&](u32 level) {
        const u32 width = std::max(info.size.width >> level, 1u);
        const u32 height = std::max(info.size.height >> level, 1u);
        return info.props.is_block
                   ? Common::DivCeil(width, 4u) * Common::DivCeil(height, 4u) * (info.num_bits / 8)
                   : width * height * (info.num_bits / 8);
    };
    const auto level_copy = [&](u32 level, u64 offset) {
        return vk::BufferImageCopy{
            .bufferOffset = offset,
            .imageSubresource = {.aspectMask = vk::ImageAspectFlagBits::eColor,
                                 .mipLevel = level,
                                 .baseArrayLayer = 0,
                                 .layerCount = 1},
            .imageOffset = {0, 0, 0},
            .imageExtent = {std::max(info.size.width >> level, 1u),
                            std::max(info.size.height >> level, 1u), 1},
        };
    };
    // Unknown glyph readbacks are diagnostic only: do not stall normal prompt rendering.
    const bool glyph_like = info.size.width == 128 && info.size.height == 128 &&
                            info.resources.levels == 8 &&
                            info.pixel_format == vk::Format::eR8G8B8A8Srgb;
    const bool unknown_glyph =
        dump_unknown && !dumping && glyph_like &&
        std::ranges::none_of(packs, [&](const PackFiles& files) { return files.contains(hash); });
    if (dumping || unknown_glyph) {
        // SOTC_TEXDUMP=<n> with n > 1 dumps only n x n textures (128 = button glyphs).
        static const u32 only_size = dumping ? u32(std::atoi(std::getenv("SOTC_TEXDUMP"))) : 0;
        if (only_size > 1 && (info.size.width != only_size || info.size.height != only_size)) {
            return;
        }
        static std::unordered_set<u64> dumped;
        if (!dumped.insert(hash).second) {
            return;
        }
        const char* folder = dumping ? "dump" : "unknown";
        std::filesystem::create_directories(dir / folder);
        if (unknown_glyph &&
            std::filesystem::exists(dir / folder / fmt::format("{:016x}.raw", hash))) {
            return;
        }
        const u32 size = level_size(0);
        const auto download = runtime.GetStagingPool().Request(size, MemoryType::HostCached, 16);
        const auto copy = level_copy(0, download.offset);
        runtime.DownloadImage(&image, download.buffer, std::span{&copy, 1});
        scheduler.Finish();
        download.Invalidate();
        const auto name =
            unknown_glyph
                ? fmt::format("{:016x}.raw", hash)
                : fmt::format("{:016x}_{}x{}_m{}_{}.raw", hash, info.size.width, info.size.height,
                              info.resources.levels, vk::to_string(info.pixel_format));
        Common::FS::IOFile file{dir / folder / name, Common::FS::FileAccessMode::Create};
        file.WriteRaw<u8>(download.mapped, size);
        if (dumping) {
            return;
        }
    }
    // Remember every image some set replaces, so a change of prompt style can refresh it.
    if (std::ranges::any_of(packs, [&](const PackFiles& files) { return files.contains(hash); })) {
        const std::pair<VAddr, u64> range{info.guest_address, info.guest_size};
        if (std::ranges::find(pack_ranges, range) == pack_ranges.end()) {
            pack_ranges.push_back(range);
        }
    }
    const PromptSet prompt_set = ActivePromptSet();
    const PackFiles& pack = packs[size_t(prompt_set)];
    const auto it = pack.find(hash);
    if (it == pack.end()) {
        return;
    }
    const auto& texture = it->second;
    if (!texture.regions.empty() && (info.size.width != 512 || info.size.height != 512 ||
                                     (info.pixel_format != vk::Format::eR8G8B8A8Srgb &&
                                      info.pixel_format != vk::Format::eR8G8B8A8Unorm))) {
        return;
    }
    const std::vector<u8>& data = texture.data;
    const auto upload = runtime.GetStagingPool().Request(data.size(), MemoryType::HostUncached, 16);
    std::memcpy(upload.mapped, data.data(), data.size());
    upload.Flush();
    SmallVector<vk::BufferImageCopy, 64> copies;
    if (!texture.regions.empty()) {
        for (auto copy : texture.regions) {
            copy.bufferOffset += upload.offset;
            copies.push_back(copy);
        }
        runtime.UploadImage(&image, upload.buffer, copies);
        return;
    }
    u64 offset = 0;
    for (u32 level = 0; level < info.resources.levels && offset + level_size(level) <= data.size();
         ++level) {
        copies.push_back(level_copy(level, upload.offset + offset));
        offset += level_size(level);
    }
    if (!copies.empty()) {
        runtime.UploadImage(&image, upload.buffer, copies);
    }
}

vk::Sampler TextureCache::GetSampler(const AmdGpu::Sampler& sharp,
                                     AmdGpu::BorderColorBuffer border_color_base,
                                     const bool is_depth) {
    // Compare and plain uses of one S# need separate samplers.
    const u64 hash = HashCombine(XXH3_64bits(&sharp, sizeof(sharp)), is_depth);
    const auto [it, new_sampler] = samplers.try_emplace(hash);
    if (new_sampler) {
        it->second = slot_samplers.Insert(instance, sharp, border_color_base, is_depth);
        Sampler& sampler = slot_samplers[it->second];
        sampler.hash = hash;
        sampler_lru_cache.Insert(sampler, gc_tick);
    }

    Sampler& sampler = slot_samplers[it->second];
    sampler_lru_cache.Touch(sampler, gc_tick);
    return sampler.Handle();
}

void TextureCache::RegisterImage(ImageId image_id) {
    ++image_set_generation;
    Image& image = slot_images[image_id];
    ASSERT_MSG(False(image.flags & ImageFlagBits::Registered),
               "Trying to register an already registered image");
    image.flags |= ImageFlagBits::Registered;
    image_lru_cache.Insert(image, gc_tick);
    const auto& info = image.info;
    ASSERT_MSG((info.guest_address & 0xff) == 0, "Trying to register an unaligned image");
    ForEachPage(info.guest_address, info.guest_size, [this, image_id, info](u64 page) {
        page_table[page].entries.emplace_back(BucketEntry{
            .key = u32(info.guest_address >> 8),
            .size = info.guest_size,
            .id = image_id,
        });
    });
}

void TextureCache::UnregisterImage(ImageId image_id) {
    ++image_set_generation;
    Image& image = slot_images[image_id];
    ASSERT_MSG(True(image.flags & ImageFlagBits::Registered),
               "Trying to unregister an already unregistered image");
    image.flags &= ~ImageFlagBits::Registered;
    image_lru_cache.Free(image);
    ForEachPage(image.info.guest_address, image.info.guest_size, [this, image_id](u64 page) {
        const auto page_it = page_table.find(page);
        ASSERT_MSG(page_it, "Unregistering unregistered page={:#x}", page << Traits::PAGE_BITS);
        auto& entries = page_it->entries;
        const auto vector_it = std::ranges::find(entries, image_id, &BucketEntry::id);
        ASSERT_MSG(vector_it != entries.end(), "Unregistering unregistered image in page={:#x}",
                   page << Traits::PAGE_BITS);
        entries.erase(vector_it);
    });
}

void TextureCache::TrackImage(ImageId image_id) {
    auto& image = slot_images[image_id];
    if (False(image.flags & ImageFlagBits::Registered)) {
        return;
    }
    const auto image_begin = image.info.guest_address;
    const auto image_end = image.info.guest_address + image.info.guest_size;
    if (image_begin == image.track_addr && image_end == image.track_addr_end) {
        return;
    }

    std::scoped_lock lk{image.mutex};
    if (image.IsUntracked()) {
        tracker.UpdatePageWatchers(image_begin, image.info.guest_size, PageOp::Track);
    } else {
        if (image_begin < image.track_addr) {
            tracker.UpdatePageWatchers(image_begin, image.track_addr - image_begin, PageOp::Track);
        }
        if (image.track_addr_end < image_end) {
            tracker.UpdatePageWatchers(image.track_addr_end, image_end - image.track_addr_end,
                                       PageOp::Track);
        }
    }
    image.track_addr = image_begin;
    image.track_addr_end = image_end;
}

void TextureCache::UntrackImage(ImageId image_id) {
    auto& image = slot_images[image_id];
    if (image.IsUntracked()) {
        return;
    }
    const auto addr = image.track_addr;
    const auto size = image.track_addr_end - image.track_addr;
    if (size != 0) {
        tracker.UpdatePageWatchers(addr, size, PageOp::Untrack);
    }
    image.track_addr = 0;
    image.track_addr_end = 0;
}

void TextureCache::UntrackImageHead(ImageId image_id) {
    auto& image = slot_images[image_id];
    const auto image_begin = image.info.guest_address;
    if (image.IsUntracked() || image_begin < image.track_addr) {
        return;
    }
    const auto addr = tracker.GetNextPageAddr(image_begin);
    const auto size = addr - image_begin;
    tracker.UpdatePageWatchers(image_begin, size, PageOp::Untrack);

    image.track_addr = addr;
    if (image.track_addr == image.track_addr_end) {
        // This image spans only 2 pages and both are modified,
        // but the image itself was not directly affected.
        // Cehck its hash later.
        MarkAsMaybeDirty(image_id, image);
    }
}

void TextureCache::UntrackImageTail(ImageId image_id) {
    auto& image = slot_images[image_id];
    const auto image_end = image.info.guest_address + image.info.guest_size;
    if (image.IsUntracked() || image.track_addr_end < image_end) {
        return;
    }
    ASSERT(image.track_addr_end != 0);
    const auto addr = tracker.GetPageAddr(image_end);
    const auto size = image_end - addr;
    image.track_addr_end = addr;
    if (image.track_addr == image.track_addr_end) {
        // This image spans only 2 pages and both are modified,
        // but the image itself was not directly affected.
        // Cehck its hash later.
        MarkAsMaybeDirty(image_id, image);
    }
    tracker.UpdatePageWatchers(addr, size, PageOp::Untrack);
}

void TextureCache::GarbageCollectImages() {
    const auto refresh_usage = [&] {
        // Includes parked twins, alternate sample backings and deferred destruction.
        total_used_memory = instance.CanReportMemoryUsage() ? instance.GetDeviceMemoryUsage()
                                                            : UniqueImage::AllocatedBytes();
    };
    const auto image_pool_pressured = [&] { return slot_images.Size() >= MAX_IMAGES / 2; };
    refresh_usage();
    if (total_used_memory < trigger_gc_memory && !image_pool_pressured()) {
        return;
    }
    const bool pressured = image_pool_pressured() || total_used_memory >= pressure_gc_memory;
    const bool critical = total_used_memory >= critical_gc_memory;
    const u64 age = std::min<u64>(critical ? 1 : pressured ? 8 : 16, gc_tick);
    const size_t limit = critical ? 40 : pressured ? 20 : 10;
    size_t scanned = 0;
    size_t retained = 0;
    SmallVector<ImageId, 40> candidates;
    image_lru_cache.ForEachItemBelow(gc_tick - age, [&](Image& image) {
        if (candidates.size() >= limit || ++scanned > 256) {
            return true;
        }
        const bool download = image.SafeToDownload();
        // Uncertain producer ownership is retained, even if a hash happens to match.
        if (download && (!pressured || !image.CanBeDownloaded())) {
            ++retained;
            image_lru_cache.Touch(image, gc_tick);
            return false;
        }
        candidates.push_back(slot_images.GetSlotId(image));
        return false;
    });
    size_t evicted = 0;
    for (const auto image_id : candidates) {
        Image& image = slot_images[image_id];
        if (image.SafeToDownload() && !DownloadImageMemory(image_id)) {
            ++retained;
            image_lru_cache.Touch(image, gc_tick);
            continue;
        }
        FreeImage(image_id);
        ++evicted;
    }
    if (pressured && evicted != 0) {
        // Actual bytes and slots remain charged until deferred destruction has executed.
        scheduler.Finish();
        scheduler.PopPendingOperations();
        refresh_usage();
    }
    static const bool stats = std::getenv("SHAD_GC_STATS") != nullptr;
    if (stats && (evicted != 0 || (gc_tick % 120) == 0)) {
        LOG_INFO(Render_Vulkan,
                 "GC: tick={} slots={} allocated={} usage={} pressure={} critical={} "
                 "scanned={} retained={} evicted={}",
                 gc_tick, slot_images.Size(), UniqueImage::AllocatedBytes(), total_used_memory,
                 pressured, critical, scanned, retained, evicted);
    }
}

void TextureCache::GarbageCollectSamplers() {
    total_used_samplers = samplers.size();
    if (total_used_samplers < trigger_gc_samplers) {
        return;
    }
    bool pressured = false;
    bool aggresive = false;
    u64 ticks_to_destroy = 0;
    size_t num_deletions = 0;

    const auto configure = [&](bool allow_aggressive) {
        pressured = total_used_samplers >= pressure_gc_samplers;
        aggresive = allow_aggressive && total_used_samplers >= critical_gc_samplers;
        ticks_to_destroy = aggresive ? 160 : pressured ? 80 : 16;
        ticks_to_destroy = std::min(ticks_to_destroy, gc_tick);
        num_deletions = aggresive ? 40 : pressured ? 20 : 10;
    };
    const auto clean_up = [&](Sampler& sampler) {
        if (num_deletions == 0) {
            return true;
        }
        --num_deletions;
        sampler_lru_cache.Free(sampler);
        samplers.erase(sampler.hash);
        const auto sampler_id = slot_samplers.GetSlotId(sampler);
        slot_samplers.Erase(sampler_id);
        return false;
    };

    // Try to remove anything old enough and not high priority.
    configure(false);
    sampler_lru_cache.ForEachItemBelow(gc_tick - ticks_to_destroy, clean_up);

    if (total_used_samplers >= critical_gc_samplers) {
        // If we are still over the critical limit, run an aggressive GC
        configure(true);
        sampler_lru_cache.ForEachItemBelow(gc_tick - ticks_to_destroy, clean_up);
    }
}

void TextureCache::RunGarbageCollector() {
    // The player picked up another input device: have the prompt glyphs uploaded again, which
    // runs them through the texture pack of the new style.
    const bool reload = g_pack_reload.exchange(false);
    if (reload) {
        g_pack_files_stale = true;
    }
    const PromptSet prompt_set = ActivePromptSet();
    if ((reload || pack_applied_set != prompt_set) && !pack_ranges.empty()) {
        pack_applied_set = prompt_set;
        for (const auto& [address, size] : pack_ranges) {
            InvalidateMemory(address, size);
        }
    }
    GarbageCollectImages();
    GarbageCollectSamplers();
    ++gc_tick;
}

void TextureCache::DeleteImage(ImageId image_id) {
    Image& image = slot_images[image_id];
    ASSERT_MSG(image.IsUntracked(), "Image was not untracked");
    ASSERT_MSG(False(image.flags & ImageFlagBits::Registered), "Image was not unregistered");

    // Remove any registered meta areas.
    const auto& meta_info = image.info.meta_info;
    if (meta_info.cmask_addr) {
        UnregisterMeta(meta_info.cmask_addr, image.image_uid);
    }
    if (meta_info.fmask_addr) {
        UnregisterMeta(meta_info.fmask_addr, image.image_uid);
    }
    if (meta_info.htile_addr) {
        UnregisterMeta(meta_info.htile_addr, image.image_uid);
    }

    {
        std::unique_lock lk{download_images_mutex};
        if (download_images.contains(image_id)) {
            download_images.erase(image_id);
        }
    }

    // Reclaim image and any image views it references.
    scheduler.DeferOperation([this, image_id] {
        Image& image = slot_images[image_id];
        for (auto& backing : image.backing_images) {
            for (const ImageViewId image_view_id : backing.image_view_ids) {
                slot_image_views.Erase(image_view_id);
            }
        }
        slot_images.Erase(image_id);
    });
}

} // namespace VideoCore
