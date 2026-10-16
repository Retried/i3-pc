#!/bin/bash
# Copy the freshly built runtime to bin/i3.exe (the binary the tests and launcher use).
set -eu
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
b="${1:-$repo/runtime/Build/w1-x64-Clang-RelWithDebInfo}"
test -f "$b/shadps4.exe" || { echo "Missing build: $b/shadps4.exe" >&2; exit 1; }
mkdir -p "$repo/bin"
cp "$b/shadps4.exe" "$repo/bin/i3.exe"
if test -f "$b/shadps4.pdb"; then cp "$b/shadps4.pdb" "$repo/bin/shadps4.pdb"; fi
echo installed
