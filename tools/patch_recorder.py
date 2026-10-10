"""One-off source patch: in-process gameplay recorder (frames + audio) for test runs."""
import os

SRC = 'D:/i3-pc/runtime/src/'


def rw(path, pairs, includes=()):
    p = SRC + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert a in s, (path, a[:60])
        s = s.replace(a, b, 1)
    for inc in includes:
        if inc not in s:
            i = s.index('#include')
            s = s[:i] + inc + '\n' + s[i:]
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


open(SRC + 'common/recording.h', 'w', encoding='utf-8', newline='\n').write('''// SPDX-FileCopyrightText: Copyright 2026 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <atomic>

namespace Common {

/// Gameplay recording for test runs (script actions "rec=on" / "rec=off"): while set, the
/// presenter appends half-size RGB frames at 30 per second to <user dir>/capture/frames.rgb
/// and the audio output appends its float samples to <user dir>/capture/audio.f32.
inline std::atomic<bool> g_recording{false};

} // namespace Common
''')

SAVE_FRAME = '''// Recording (see common/recording.h): one frame, halved in both directions, written as RGB24
// as many times as 1/30 s slots have passed since the previous one, so the file plays back at
// a constant 30 frames per second whatever the frame rate of the game is.
static void SaveRecordedFrame(const ScreenshotReadback& readback) {
    static std::FILE* file = nullptr;
    static u64 frames_written = 0;
    static std::chrono::steady_clock::time_point start;
    std::vector<u8> rgba;
    if (!ConvertReadbackToRgba8(readback, rgba)) {
        return;
    }
    if (file == nullptr) {
        const auto dir = Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "capture";
        std::filesystem::create_directories(dir);
        file = std::fopen((dir / "frames.rgb").string().c_str(), "wb");
        if (file == nullptr) {
            return;
        }
        if (std::FILE* info = std::fopen((dir / "frames.txt").string().c_str(), "w")) {
            std::fprintf(info, "%u %u 30", readback.width / 2, readback.height / 2);
            std::fclose(info);
        }
        start = std::chrono::steady_clock::now();
    }
    const u32 width = readback.width / 2;
    const u32 height = readback.height / 2;
    std::vector<u8> rgb(size_t(width) * height * 3);
    for (u32 y = 0; y < height; ++y) {
        const u8* row0 = rgba.data() + size_t(y) * 2 * readback.width * 4;
        const u8* row1 = row0 + size_t(readback.width) * 4;
        u8* out = rgb.data() + size_t(y) * width * 3;
        for (u32 x = 0; x < width; ++x) {
            for (u32 c = 0; c < 3; ++c) {
                out[x * 3 + c] = u8((row0[x * 8 + c] + row0[x * 8 + 4 + c] + row1[x * 8 + c] +
                                     row1[x * 8 + 4 + c] + 2) / 4);
            }
        }
    }
    const double elapsed =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    const u64 due = u64(elapsed * 30.0) + 1;
    for (; frames_written < due; ++frames_written) {
        std::fwrite(rgb.data(), 1, rgb.size(), file);
    }
    std::fflush(file);
}

static void SavePendingScreenshot(const ScreenshotReadback& readback) {'''

CAPTURE = '''    const u32 capture_game_only_count = VideoCore::ConsumeGameOnlyScreenshotRequests();
    std::optional<ScreenshotReadback> pending_screenshot;
    std::optional<ScreenshotReadback> recorded_frame;
    if (Common::g_recording.load(std::memory_order_relaxed)) {
        // At most 30 captures a second.
        static std::chrono::steady_clock::time_point last_capture;
        const auto now = std::chrono::steady_clock::now();
        if (now - last_capture >= std::chrono::milliseconds(33)) {
            last_capture = now;
            auto& readback = recorded_frame.emplace(
                instance, ScreenshotKind::GameOnly, std::vector<std::filesystem::path>{},
                image_size.width, image_size.height, view_info.format, false);
            const vk::BufferImageCopy copy_region = {
                .imageSubresource{.aspectMask = vk::ImageAspectFlagBits::eColor,
                                  .mipLevel = 0,
                                  .baseArrayLayer = 0,
                                  .layerCount = 1},
                .imageExtent = {readback.width, readback.height, 1},
            };
            runtime.DownloadImage(&image, &readback.buffer, std::span{&copy_region, 1});
        }
    }
'''

DEFER = '''    if (recorded_frame) {
        draw_scheduler.DeferPriorityOperation([deferred_frame = std::move(recorded_frame)]() {
            SaveRecordedFrame(deferred_frame.value());
        });
    }
    if (pending_screenshot) {
        draw_scheduler.DeferPriorityOperation('''

rw('video_core/renderer_vulkan/vk_presenter.cpp', [
    ('static void SavePendingScreenshot(const ScreenshotReadback& readback) {', SAVE_FRAME),
    ('''    const u32 capture_game_only_count = VideoCore::ConsumeGameOnlyScreenshotRequests();
    std::optional<ScreenshotReadback> pending_screenshot;
''', CAPTURE),
    ('''    if (pending_screenshot) {
        draw_scheduler.DeferPriorityOperation(''', DEFER),
], includes=('#include "common/recording.h"', '#include <chrono>', '#include <cstdio>'))

AUDIO = '''        if (Common::g_recording.load(std::memory_order_relaxed)) {
            // Recording (see common/recording.h): the stereo output, before muting.
            static std::FILE* file = nullptr;
            if (internal_buffer_size / sizeof(float) / buffer_frames == 2) {
                if (file == nullptr) {
                    const auto dir =
                        Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "capture";
                    std::filesystem::create_directories(dir);
                    file = std::fopen((dir / "audio.f32").string().c_str(), "wb");
                }
                if (file != nullptr) {
                    std::fwrite(internal_buffer, 1, internal_buffer_size, file);
                }
            }
        }
        static const bool metering = std::getenv("I3_AUDIO_METER") != nullptr;
'''
rw('core/libraries/audio/sdl_audio_out.cpp', [
    ('        static const bool metering = std::getenv("I3_AUDIO_METER") != nullptr;\n', AUDIO),
], includes=('#include "common/recording.h"', '#include "common/path_util.h"', '#include <cstdio>',
             '#include <filesystem>'))

rw('sdl_window.cpp', [
    ('        } else if (action.starts_with("aim=")) {',
     '''        } else if (action == "rec=on" || action == "rec=off") {
            Common::g_recording.store(action == "rec=on", std::memory_order_relaxed);
        } else if (action.starts_with("aim=")) {'''),
], includes=('#include "common/recording.h"',))
print('patched')
