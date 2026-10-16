#!/bin/bash
# Portable entry point for the existing frame-time capture and scripted routes.
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON3_EXECUTABLE:-python}" "$repo/tools/benchmark.py" "$@"
