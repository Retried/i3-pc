#!/bin/bash
# A/B the existing direct-draw fast path with the portable benchmark runner.
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$repo/bench.sh" run --matrix "$repo/docs/benchmark-fastpath.json" --caches warm "$@"
