#!/bin/bash
# Profile an explicitly selected replay; later city fixtures can use their own matrix.
set -e
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$repo/bench.sh" run --matrix "$repo/docs/benchmark-opening.json" --caches warm --repeats 1 --profile "$@"
