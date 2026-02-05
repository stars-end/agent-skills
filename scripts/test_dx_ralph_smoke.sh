#!/usr/bin/env bash
set -euo pipefail

echo "=== dx-ralph smoke ==="

echo "Running doctor..."
python3 "$(cd "$(dirname "$0")" && pwd)/dx-ralph.py" doctor

echo
echo "OK: doctor passed."
echo "Tip: to validate planning on a real epic, run:"
echo "  python3 scripts/dx-ralph.py plan --universe <bd-epic-id>"

