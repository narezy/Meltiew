#!/usr/bin/env bash
# The scripting runtime lives in server/src/studio/runtime; the app carries a copy.
set -euo pipefail
cd "$(dirname "$0")/.."
cp server/src/studio/runtime/runtime.luau server/src/studio/runtime/classes.json client/studio/runtime/
echo "runtime synced"
