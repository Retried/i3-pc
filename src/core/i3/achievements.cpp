// SPDX-License-Identifier: GPL-2.0-or-later

// The game reports unlocks through sceNpTrophyUnlockTrophy. The names and descriptions in its
// trophy package are encrypted with a console key this build does not have, so they are read
// from a text file the player can provide; the icons in the package are plain PNG files and are
// copied out of the installed game for the unlock notice.

#include <array>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <vector>
#include <fmt/format.h>

#include "common/logging/log.h"
#include "common/path_util.h"
#include "common/singleton.h"
#include "core/file_sys/fs.h"
#include "core/i3/achievements.h"
#include "core/libraries/np/trophy_ui.h"

namespace I3::Achievements {

namespace {

constexpr int NumTrophies = 48;

struct Entry {
    std::string name;
    std::string description;
    u64 unlocked_at = 0;
};

std::array<Entry, NumTrophies> entries;
std::mutex mutex;
bool loaded = false;

std::filesystem::path BaseDir() {
    return Common::FS::GetUserPath(Common::FS::PathType::UserDir) / "i3_achievements";
}

std::filesystem::path IconPath(s32 id) {
    return BaseDir() / "icons" / fmt::format("TROP{:03}.PNG", id);
}

u32 ReadBe32(const u8* p) {
    return (u32(p[0]) << 24) | (u32(p[1]) << 16) | (u32(p[2]) << 8) | u32(p[3]);
}

u64 ReadBe64(const u8* p) {
    return (u64(ReadBe32(p)) << 32) | ReadBe32(p + 4);
}

/// Copies the trophy icons out of the trophy package of the game (stored unencrypted there).
void ExtractIcons() {
    std::error_code ec;
    if (std::filesystem::exists(IconPath(0), ec)) {
        return;
    }
    auto* mnt = Common::Singleton<Core::FileSys::MntPoints>::Instance();
    const auto trp_path = mnt->GetHostPath("/app0/sce_sys/trophy/trophy00.trp");
    std::ifstream file(trp_path, std::ios::binary);
    std::array<u8, 0x60> header{};
    file.read(reinterpret_cast<char*>(header.data()), header.size());
    if (!file || ReadBe32(header.data()) != 0xDCA24D00) {
        return;
    }
    const u32 count = ReadBe32(header.data() + 16);
    const u32 entry_size = ReadBe32(header.data() + 20);
    if (entry_size < 48 || entry_size > 4096 || count > 4096) {
        return;
    }
    std::filesystem::create_directories(BaseDir() / "icons", ec);
    std::vector<u8> entry(entry_size);
    for (u32 i = 0; i < count; i++) {
        file.seekg(0x60 + u64(i) * entry_size);
        file.read(reinterpret_cast<char*>(entry.data()), entry_size);
        if (!file) {
            return;
        }
        const char* raw_name = reinterpret_cast<const char*>(entry.data());
        const std::string name(raw_name, strnlen(raw_name, 32));
        if (!name.starts_with("TROP") || !name.ends_with(".PNG")) {
            continue;
        }
        const u64 pos = ReadBe64(entry.data() + 32);
        const u64 len = ReadBe64(entry.data() + 40);
        if (len > 16 * 1024 * 1024) {
            continue;
        }
        std::vector<char> data(len);
        file.seekg(pos);
        file.read(data.data(), len);
        if (!file) {
            file.clear();
            continue;
        }
        std::ofstream out(BaseDir() / "icons" / name, std::ios::binary);
        out.write(data.data(), data.size());
    }
}

void Save() {
    std::error_code ec;
    std::filesystem::create_directories(BaseDir(), ec);
    const auto path = BaseDir() / "unlocked.txt";
    const auto temp = BaseDir() / "unlocked.tmp";
    {
        std::ofstream out(temp, std::ios::trunc);
        out << "# inFAMOUS Second Son achievements: <id> <unix time unlocked>\n";
        for (size_t i = 0; i < entries.size(); i++) {
            if (entries[i].unlocked_at != 0) {
                out << i << ' ' << entries[i].unlocked_at << '\n';
            }
        }
    }
    std::filesystem::rename(temp, path, ec);
}

void EnsureLoaded() {
    if (loaded) {
        return;
    }
    loaded = true;
    for (size_t i = 0; i < entries.size(); i++) {
        entries[i].name = fmt::format("Trophy {}", i + 1);
    }
    ExtractIcons();
    std::string line;
    std::ifstream names(BaseDir() / "names.txt");
    while (std::getline(names, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        const auto first = line.find('\t');
        if (first == std::string::npos) {
            continue;
        }
        const auto second = line.find('\t', first + 1);
        const unsigned id = static_cast<unsigned>(std::atoi(line.substr(0, first).c_str()));
        if (id >= entries.size()) {
            continue;
        }
        entries[id].name = line.substr(
            first + 1, second == std::string::npos ? std::string::npos : second - first - 1);
        entries[id].description =
            second == std::string::npos ? std::string{} : line.substr(second + 1);
    }
    std::ifstream in(BaseDir() / "unlocked.txt");
    while (std::getline(in, line)) {
        unsigned id = 0;
        unsigned long long when = 0;
        if (std::sscanf(line.c_str(), "%u %llu", &id, &when) == 2 && id < entries.size()) {
            entries[id].unlocked_at = when;
        }
    }
}

} // namespace

int Count() {
    return NumTrophies;
}

UnlockResult Unlock(s32 id) {
    std::scoped_lock lock{mutex};
    EnsureLoaded();
    if (id < 0 || id >= NumTrophies) {
        return UnlockResult::UnknownId;
    }
    if (entries[id].unlocked_at != 0) {
        return UnlockResult::AlreadyUnlocked;
    }
    entries[id].unlocked_at = std::chrono::duration_cast<std::chrono::seconds>(
                                  std::chrono::system_clock::now().time_since_epoch())
                                  .count();
    Save();
    LOG_INFO(Lib_NpTrophy, "Achievement unlocked: {} ({})", entries[id].name, id);
    Libraries::Np::NpTrophy::AddTrophyToQueue(IconPath(id), entries[id].name, "B");
    return UnlockResult::Unlocked;
}

std::string Name(s32 id) {
    std::scoped_lock lock{mutex};
    EnsureLoaded();
    return id >= 0 && id < NumTrophies ? entries[id].name : std::string{};
}

std::string Description(s32 id) {
    std::scoped_lock lock{mutex};
    EnsureLoaded();
    return id >= 0 && id < NumTrophies ? entries[id].description : std::string{};
}

u64 UnlockedAt(s32 id) {
    std::scoped_lock lock{mutex};
    EnsureLoaded();
    return id >= 0 && id < NumTrophies ? entries[id].unlocked_at : 0;
}

int UnlockedCount() {
    std::scoped_lock lock{mutex};
    EnsureLoaded();
    int count = 0;
    for (const auto& entry : entries) {
        count += entry.unlocked_at != 0;
    }
    return count;
}

} // namespace I3::Achievements
