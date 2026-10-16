#!/bin/bash
# Legacy A/B entry point; the same runner now records independent alternated repeats.
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$repo/abtest.sh" "$@"
