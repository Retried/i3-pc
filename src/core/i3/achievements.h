// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>
#include "common/types.h"

// Achievements of the inFAMOUS Second Son build: the trophy unlocks the game reports, kept in
// the user folder and listed in the PC options.
namespace I3::Achievements {

enum class UnlockResult { Unlocked, AlreadyUnlocked, UnknownId };

/// Number of trophies in the game.
int Count();

/// Records the unlock and shows the notification.
UnlockResult Unlock(s32 id);

/// Name and description of a trophy. They are text of the game and not part of this program:
/// they come from names.txt in <user>/i3_achievements (one line per trophy: id, tab, name, tab,
/// description). Without that file the name is "Trophy <n>".
std::string Name(s32 id);
std::string Description(s32 id);

/// Unix time of the unlock, 0 while locked.
u64 UnlockedAt(s32 id);

int UnlockedCount();

} // namespace I3::Achievements
