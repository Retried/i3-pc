"""One-off source patch: memoise perfect-match texture lookups in TextureCache::FindImage."""
ROOT = 'D:/i3-pc/runtime/src/video_core/texture_cache/'


def rw(path, pairs):
    p = ROOT + path
    s = open(p, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    s = s.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))


rw('texture_cache.h', [
    ('    std::vector<std::pair<VAddr, u64>> pack_ranges;\n',
     '''    std::vector<std::pair<VAddr, u64>> pack_ranges;

    /// Remembered results of FindImage for requests that matched a cached image exactly.
    /// A heavy frame looks the same few hundred textures up thousands of times; the walk
    /// over the page table and the comparisons are skipped while the set of registered
    /// images has not changed (every register and unregister bumps the generation).
    struct FoundImage {
        u64 generation = 0;
        VAddr guest_address = 0;
        u32 guest_size = 0;
        Extent3D size{};
        vk::Format pixel_format{};
        AmdGpu::ImageType type{};
        bool exact_fmt = false;
        ImageId image_id{};
    };
    std::array<FoundImage, 2048> found_images{};
    u64 image_set_generation = 1;
'''),
])

rw('texture_cache.cpp', [
    ('''    SmallVector<ImageId, 8> image_ids;
    ForEachImageInRegion(info.guest_address, info.guest_size,
                         [&](ImageId image_id, Image& image) { image_ids.push_back(image_id); });

    ImageId image_id{};
''', '''    // I3_NO_FIND_MEMO=1 turns the lookup memo off (A/B measurement).
    static const bool memo = std::getenv("I3_NO_FIND_MEMO") == nullptr;
    FoundImage& found =
        found_images[((info.guest_address >> 12) ^ (info.guest_address >> 23) ^ info.guest_size ^
                      (u64(info.pixel_format) << 3)) &
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
'''),
    ('''        image_id = cache_id;
    }

    // Try to resolve overlaps (if any)
''', '''        image_id = cache_id;
        perfect_match = true;
    }

    // Try to resolve overlaps (if any)
'''),
    ('''    Image& image = slot_images[image_id];
    image.tick_accessed_last = scheduler.CurrentTick();
    TouchImage(image);

    // If the image requested is a subresource of the image from cache record its location.
''', '''    Image& image = slot_images[image_id];
    image.tick_accessed_last = scheduler.CurrentTick();
    TouchImage(image);

    // Only exact matches are remembered: anything resolved through an overlap, or created
    // just now (which changed the generation), goes through the full path again.
    if (memo && perfect_match && slot_images[image_id].info.guest_address == info.guest_address) {
        found = {image_set_generation, info.guest_address, info.guest_size, info.size,
                 info.pixel_format, info.type, exact_fmt, image_id};
    }

    // If the image requested is a subresource of the image from cache record its location.
'''),
])

# Every change of the registered set invalidates the memo.
p = ROOT + 'texture_cache.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')
for fn in ('void TextureCache::RegisterImage(ImageId image_id) {\n',
           'void TextureCache::UnregisterImage(ImageId image_id) {\n'):
    assert s.count(fn) == 1, fn
    s = s.replace(fn, fn + '    ++image_set_generation;\n', 1)
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
