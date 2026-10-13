// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <string>

// The language of the PC menus of the inFAMOUS Second Son build. It follows the console
// language setting, the value the game itself reads, so the menus and the game agree. The
// texts are keyed by their English wording; a language or a text without a translation is
// shown in English.
namespace I3::Lang {

/// The text in the current language, or `english` itself when there is no translation.
const char* Tr(const char* english);
std::string Tr(const std::string& english);
/// The console language id (PS4 system language numbering), read once at first use.
int Current();
/// `text` (UTF-8) in capitals: Latin, Latin-1, Latin Extended-A and Cyrillic letters. The
/// menu's headings are capitals, and std::toupper only knows ASCII.
std::string Upper(const std::string& text);

} // namespace I3::Lang
