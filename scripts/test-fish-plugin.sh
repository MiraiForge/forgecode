#!/usr/bin/env bash
# Runs every fish plugin check: generated scripts parse, `forge fish format`
# behaves, and the plugin works end to end in an interactive fish.
#
# Usage: ./scripts/test-fish-plugin.sh [path/to/forge]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_BIN="${1:-${FORGE_BIN:-${SCRIPT_DIR}/../target/debug/forge}}"

if [[ ! -x "$FORGE_BIN" ]]; then
    echo "forge binary not found at ${FORGE_BIN}; run: cargo build -p forge_main" >&2
    exit 1
fi
command -v fish >/dev/null || { echo "fish is not installed" >&2; exit 1; }

echo "==> fish $(fish --version | awk '{print $3}')"

echo "==> generated plugin and theme parse"
"$FORGE_BIN" fish plugin </dev/null | fish --no-execute
"$FORGE_BIN" fish theme </dev/null | fish --no-execute

echo "==> forge fish format"
FORGE_BIN="$FORGE_BIN" fish "${SCRIPT_DIR}/test-fish-utils.fish"

echo "==> interactive smoke test"
python3 "${SCRIPT_DIR}/test-fish-plugin.py" "$FORGE_BIN"
