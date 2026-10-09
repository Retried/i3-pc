// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

// What the inFAMOUS Second Son build does once, the first time it runs on a PC.
namespace I3::FirstRun {

/// Picks display and effect settings for this PC (display resolution and refresh rate, GPU
/// memory, CPU cores, RAM) and saves them. Runs once: the marker file it leaves keeps later
/// starts, and anything the player changed since, untouched. Call after the settings were
/// loaded and before the window is created.
void AdjustSettings();

/// Call before the settings are loaded (loading creates the file): remembers whether this
/// install already had a settings file. AdjustSettings only acts on an install that had none,
/// so nothing a player has set is ever replaced.
void NoteExistingSettings();

/// The two opening lines on a black screen, ahead of the game's own intros; the game is held
/// while they show. Draws nothing after the first run. Called once per frame.
void DrawIntro();

/// True while the opening lines are on screen (input belongs to nobody then).
bool IntroActive();

} // namespace I3::FirstRun
