inFAMOUS Second Son - PC build (work in progress)
=================================================

Start:     the Desktop or Start menu shortcut, or "inFAMOUS Second Son.exe" here
Shortcuts: Install.bat creates them again (Install.bat -Remove deletes them)
Settings:  Settings.bat  (frame rate cap, VSync, fullscreen, window size, FSR upscaling,
                          language)
In game:   F2 (or L3 + R3 on a controller) opens PC OPTIONS over the running game:
             CONTROLS  every action; confirm, then press the key or mouse button to use.
                       Applies at once, and the button icons are redrawn to match.
             GRAPHICS  frame rate cap and VSync (take effect at the next start); fullscreen,
                       window size, FSR upscaling, sharpening, frame rate counter (at once).
                       Effects preset and switches (anti-aliasing, wet reflections, glow)
                       and Game Frame Limit, which lifts the game's own 30 FPS limit.
                       Sun Shadows and Light Shadows: how often the shadow maps are redrawn
                       (Every Frame, Every 2nd Frame, Off). The biggest frame rate lever:
                       Every 2nd Frame is faster with the same picture when standing; Off is
                       fastest and removes those shadows. Shadow Detail (Full, Reduced,
                       Low) leaves small objects out of the sun's shadows.
                       Shadow Preset (Original, Balanced, Fast, Off) sets all three.
             ACHIEVEMENTS  the trophies of the game: locked, or the date unlocked. They are
                       saved in user\i3_achievements. Names show as "Trophy 1" to "Trophy 48"
                       unless user\i3_achievements\names.txt lists them (id, tab, name, tab,
                       description, one per line).
Keys:      Keys.bat      the same key bindings from outside the game
Game data: D:\Games\CUSA00004 (read only, never modified; path in game_path.txt)
Saves:     user\home\1000\savedata\CUSA00004
Bindings:  user\input_config\CUSA00004.ini  (F8 reloads it while the game runs)

Button icons follow the device in use: key caps while you play on keyboard and mouse,
the PlayStation icons when you touch a controller.

Keyboard and mouse
------------------
Move                W A S D
Camera              mouse (F7 toggles mouse capture)
Main attack (R2)    left mouse button
Aim (L2)            right mouse button
Heavy attack (R1)   middle mouse button / Q
Special power (L1)  E
Jump (cross)        Space
Dash (circle)       Left Shift / Left Ctrl / Backspace
Melee (square)      F
Karmic (triangle)   R
L3 / R3             V / Z
Touchpad press      T / Tab
Touchpad swipe      I up, K down, J left, L right
Touchpad, both thumbs  hold U  (prompts showing a touchpad with two fingerprints,
                       e.g. MOVE CAR; the prompt itself shows no key)
D-pad               arrow keys / 1 2 3 4
Options (pause)     Esc

Motion controls (the game asks for them, e.g. spray cans):
Hold G              controller held sideways; while held, W A S D or the mouse aim the can
Hold H              shake
Spray               hold G, then hold the left mouse button and aim

A controller (Xbox, DualShock, DualSense) works alongside the keyboard.

Runtime hotkeys: F11 fullscreen, F10 FPS counter, F9 pause, F12 screenshot.

Status (2026-10-09)
-------------------
Verified: boot, title, new game, intro, spray tutorial (60 FPS), cutscenes and the cannery
interior (about 32 FPS) with correct graphics; autosave and Continue; sideways, shake and spray
aim from the keyboard; walking, mouse camera, jump, pause menu; sound output measured clean.
Frame rate: 60 FPS cap by default; light scenes reach 107-120 FPS with the 120 cap, heavy
scenes (interiors, the crash site) sit at the game's own 30 FPS lock.
Played and verified from the keyboard up to "Find Betty" inside the fish cannery: tutorial,
crash site, Lift Wreckage (swipe up), gaining the smoke power, Smoke Dash through fallen trees
and the cannery gate, Move Car (hold U), smoke travel through wall vents (dash into the round
red vents), melee with the chain (F), the cutscenes in between, a failed mission and its reload.
Reached after that: the main cannery hall and the objective "Catch Hank".
Not verified yet: ranged attacks, enemies, the other powers and the city.
The PS4 Pro mode of the game does not run in this build.

Credits
-------
The program is a build for this one game made from the shadPS4 runtime source
(https://github.com/shadps4-emu/shadPS4, GPL-2.0-or-later) with game-specific changes.
Its licence terms apply to the program; the game data is your own PS4 copy.
