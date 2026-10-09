// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

union SDL_Event;
struct ImFont;

// The PC options overlay of the inFAMOUS Second Son build: key bindings and display settings,
// drawn over the running game. F2, or L3 + R3 on a controller, opens and closes it.
namespace I3::Menu {

void Toggle();
bool IsOpen();
/// Draws the overlay; called once per frame inside the ImGui frame.
void Draw();
/// Lets the overlay see an input event before the game does. Returns true when the event
/// belongs to the overlay (it is open, or waiting for a key to bind) and must not reach the game.
bool OnEvent(const SDL_Event& event);
/// The condensed face used for the overlay text, loaded once with the other fonts.
void SetFont(ImFont* font);

} // namespace I3::Menu
