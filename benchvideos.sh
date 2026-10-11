#!/bin/bash
# The benchmark clips for the showcase, one run each (about 2.5 minutes a clip). Direct launch:
# only in an agreed slot. Uncaptured figures are those of showcase/BENCHMARK.md.
cd /d/i3-pc || exit 1
./benchclip.sh crash_original chase full full full stand "Crash site" "Shadow Preset Original" "40 to 41 FPS"
./benchclip.sh crash_balanced chase half half reduced stand "Crash site" "Shadow Preset Balanced" "45 to 48 FPS"
./benchclip.sh crash_fast chase half off low stand "Crash site" "Shadow Preset Fast" "49 FPS"
./benchclip.sh crash_off chase off off full stand "Crash site" "Shadow Preset Off" "50 to 51 FPS"
./benchclip.sh cannery earlygame full full full stand "Fish cannery interior" "Shadow Preset Original" "38 to 41 FPS"
./benchclip.sh road fishcannery full full full road "Road to the cannery, running" "Shadow Preset Original" "46 FPS average"
./benchclip.sh city seattle full full full city "Seattle bridge, running" "Shadow Preset Original" "${CITY_FPS:-not measured yet}"
echo CLIPS_DONE
