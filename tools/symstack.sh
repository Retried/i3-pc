#!/bin/bash
# Symbolises the first crash stack in the test log against the dev build: tools/symstack.sh [log]
L=${1:-/d/i3-pc/testrun/user/log/shad_log.txt}
cp /d/i3-pc/bin/i3.exe /d/i3-pc/bin/shadps4.exe
tool=$(ls /d/sotc-pc/toolchain/*/bin/llvm-symbolizer.exe | head -1)
grep -a "access 0x" "$L" | head -1 | sed 's/.*access \(0x[0-9a-f]*\).*/access \1/'
grep -a "access 0x" "$L" | head -1 | sed 's/.*stack: //' | tr ' ' '\n' | grep "^0x7000" | head -14 | "$tool" --obj=D:/i3-pc/bin/shadps4.exe -f -C -s | grep -v "^$" | paste - - | cut -c1-150
rm -f /d/i3-pc/bin/shadps4.exe
