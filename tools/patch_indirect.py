"""One-off source patch: inFAMOUS indirect draws are drawn from the arguments that were checked."""
p = 'D:/i3-pc/runtime/src/video_core/renderer_vulkan/vk_rasterizer.cpp'
s = open(p, encoding='utf-8', newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
s = s.replace('\r\n', '\n')


def rep(a, b, n=1):
    global s
    assert s.count(a) == n, (a[:60], s.count(a))
    s = s.replace(a, b)


rep('''        static const bool check_args = Common::ElfInfo::Instance().GameSerial() != "CUSA08809";
        if (check_args) {
            u32 args[5]{};
            memory->CopySparseMemory(arg_address + offset, reinterpret_cast<u8*>(args),
                                     sizeof(args));
            constexpr u32 max_elements = 0x4000000;
            constexpr u32 max_instances = 0x100000;
            if (args[0] > max_elements || args[1] > max_instances) {
                LOG_WARNING(Render, "Dropped indirect draw at {:#x}: count {:#x}, instances {:#x}",
                            arg_address + offset, args[0], args[1]);
                ++g_stats.filtered;
                return;
            }
        }
''', '''        // Every slot of a multi draw is checked, and when the arguments live in plain guest
        // memory (nothing on the GPU wrote them) the draws are issued from the checked values
        // instead of letting the GPU read the slot again: a slot the game fills in late then
        // cannot differ between the check and the draw. A device loss was still seen with only
        // the first slot checked and limits of 64M elements and 1M instances.
        static const bool check_args = Common::ElfInfo::Instance().GameSerial() != "CUSA08809";
        checked_args.clear();
        if (check_args) {
            constexpr u32 max_elements = 0x400000;
            constexpr u32 max_instances = 0x10000;
            constexpr u32 max_slots = 256;
            const u32 slots = count_address == 0 ? std::min(max_count, max_slots) : 1;
            const bool direct = count_address == 0 && max_count <= max_slots && stride >= 16 &&
                                !buffer_cache.IsRegionGpuModified(arg_address + offset,
                                                                  u64(stride) * max_count);
            for (u32 slot = 0; slot < slots; ++slot) {
                std::array<u32, 5> args{};
                memory->CopySparseMemory(arg_address + offset + u64(slot) * stride,
                                         reinterpret_cast<u8*>(args.data()),
                                         std::min<u64>(stride, sizeof(args)));
                if (args[0] > max_elements || args[1] > max_instances) {
                    LOG_WARNING(Render,
                                "Dropped indirect draw at {:#x}: count {:#x}, instances {:#x}",
                                arg_address + offset + u64(slot) * stride, args[0], args[1]);
                    ++g_stats.filtered;
                    checked_args.clear();
                    return;
                }
                if (direct) {
                    checked_args.push_back(args);
                }
            }
        }
''')
# Fast repeat path.
rep('''                scheduler.Stream().drawIndexedIndirect(buffer->Handle(), base, max_count, stride);''',
    '''                if (!checked_args.empty()) {
                    EmitCheckedDraws(scheduler.Stream(), true);
                } else {
                    scheduler.Stream().drawIndexedIndirect(buffer->Handle(), base, max_count,
                                                           stride);
                }''')
rep('''                scheduler.Stream().drawIndirect(buffer->Handle(), base, max_count, stride);''',
    '''                if (!checked_args.empty()) {
                    EmitCheckedDraws(scheduler.Stream(), false);
                } else {
                    scheduler.Stream().drawIndirect(buffer->Handle(), base, max_count, stride);
                }''')
rep('''        } else {
            cmdbuf.drawIndexedIndirect(buffer->Handle(), base, max_count, stride);
        }
        DebugState.IncDrawCall();''', '''        } else if (!checked_args.empty()) {
            EmitCheckedDraws(cmdbuf, true);
        } else {
            cmdbuf.drawIndexedIndirect(buffer->Handle(), base, max_count, stride);
        }
        DebugState.IncDrawCall();''')
rep('''        } else {
            cmdbuf.drawIndirect(buffer->Handle(), base, max_count, stride);
        }
        DebugState.IncDrawCall();''', '''        } else if (!checked_args.empty()) {
            EmitCheckedDraws(cmdbuf, false);
        } else {
            cmdbuf.drawIndirect(buffer->Handle(), base, max_count, stride);
        }
        DebugState.IncDrawCall();''')
rep('''void Rasterizer::DrawIndirect(bool is_indexed, VAddr arg_address, u32 offset, u32 stride,''',
    '''// Indirect draw arguments read from guest memory and checked (see DrawIndirect); empty when
// the GPU is to read the argument buffer itself.
static boost::container::small_vector<std::array<u32, 5>, 4> checked_args;

template <typename Stream>
static void EmitCheckedDraws(Stream& cmdbuf, bool is_indexed) {
    for (const auto& args : checked_args) {
        if (args[0] == 0 || args[1] == 0) {
            continue;
        }
        if (is_indexed) {
            cmdbuf.drawIndexed(args[0], args[1], args[2], s32(args[3]), args[4]);
        } else {
            cmdbuf.draw(args[0], args[1], args[2], args[3]);
        }
    }
}

void Rasterizer::DrawIndirect(bool is_indexed, VAddr arg_address, u32 offset, u32 stride,''')
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', nl))
print('patched')
