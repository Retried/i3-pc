// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "common/types.h"

union SDL_Event;
struct ImFont;

// The screens of the inFAMOUS Second Son build:
// - a start screen at launch (the game itself has none: it loads the last save at once):
//   Continue, New Game, Load Game, Options, Achievements, Quit;
// - the PC settings as sections at the end of the game's own Options screen. The game draws
//   that screen itself, so the runtime watches its picture (OnProbe): when its last line is
//   selected, Down moves on into the sections added here (Graphics, Controls, Language,
//   Achievements, Exit), drawn as the rest of the same list. Up from the first of them goes
//   back to the game's lines.
namespace I3::Menu {

void Toggle();
/// The pad's Options button, after the binding layer. Returns true when the game must not see
/// it (the start screen or the opening lines are up, or the PC sections hold the input).
bool OnOptionsButton(bool pressed);
bool IsOpen();
/// Draws the overlay; called once per frame inside the ImGui frame.
void Draw();
/// Lets the overlay see an input event before the game does. Returns true when the event
/// belongs to the overlay (it is open, or waiting for a key to bind) and must not reach the game.
bool OnEvent(const SDL_Event& event);
/// The condensed face used for the overlay text, loaded once with the other fonts.
void SetFont(ImFont* font);
ImFont* Font();

/// Where the game's Options panel lies on a 1920 x 1080 frame: the area read back from the
/// game's picture to find it and its selected line, and the smaller area of its title, which
/// is all that is read during play.
constexpr float ProbeLeft = 312.0f;
constexpr float ProbeTop = 100.0f;
constexpr float ProbeRight = 1060.0f;
constexpr float ProbeBottom = 990.0f;
constexpr float TitleLeft = 405.0f;
constexpr float TitleTop = 115.0f;
constexpr float TitleRight = 540.0f;
constexpr float TitleBottom = 200.0f;
enum class Probe { None, Title, Panel };
/// The probe area in the guest frame: its pixels, and how 1080-line coordinates map onto it.
struct ProbeArea {
    u32 x, y, width, height;
    float scale; // guest pixels per 1080-line pixel
    float left;  // guest x of 1080-line x 0 (pillarbox)
    Probe kind;
};
/// What of the next frame to read back: the panel every frame while the game's Options screen
/// is up, else its title every fourth frame.
Probe WantsProbe();
/// The probe area of a presented frame as RGBA8, `area.width` x `area.height`.
void OnProbe(const u8* rgba, const ProbeArea& area);

} // namespace I3::Menu
