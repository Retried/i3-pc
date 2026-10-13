#!/bin/bash
# Everything that waits for the user's go-ahead, in one sequence (about one hour):
#   1. crashtest.sh: optimized build of the working tree and the shooting soaks (35 minutes).
#   2. If all three soaks with the fixes stayed alive: the benchmark clips on that build
#      (benchvideos.sh, seven clips, about 20 minutes). Otherwise the clips are left out.
# Results: tools/go_result.txt. Same guards as crashtest.sh. Writes SLOT_DONE at the end.
cd /d/i3-pc || exit 1
./crashtest.sh 2>&1 | tee tools/go_result.txt
rm -f SLOT_DONE
alive=$(grep -c -E "^fix[123]: alive 1 " tools/go_result.txt)
died=$(grep -c -E "^fix[123]: DIED" tools/go_result.txt)
if [ "$alive" = "3" ] && [ "$died" = "0" ] && [ ! -f HOLD ]; then
    echo "fixes passed: recording the clips on bin-fix" | tee -a tools/go_result.txt
    BIN=/d/i3-pc/bin-fix ./benchvideos.sh 2>&1 | tee -a tools/go_result.txt
else
    echo "fixes did not pass ($alive alive, $died died): no clips recorded" | tee -a tools/go_result.txt
fi
sleep 5; taskkill //IM i3.exe //F > /dev/null 2>&1
touch SLOT_DONE; date +%H:%M:%S
