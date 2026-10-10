#!/bin/bash
# Copy the freshly built runtime to bin/i3.exe (the binary the tests and launcher use).
b=/d/i3-pc/runtime/Build/x64-Clang-RelWithDebInfo
cp "$b/shadps4.exe" /d/i3-pc/bin/i3.exe && cp "$b/shadps4.pdb" /d/i3-pc/bin/shadps4.pdb && echo installed
