#!/usr/bin/env bash
set -euo pipefail

echo "=== dx-ralph smoke ==="

echo "Running doctor..."
python3 "$(cd "$(dirname "$0")" && pwd)/dx-ralph.py" doctor

echo
echo "Running smoke run (no OpenCode calls)..."
python3 scripts/dx-ralph.py run --universe bd-zxw6 --repo-map bd-zxw6=agent-skills --smoke

echo
echo "OK: doctor + smoke run passed."
echo "Tip: to validate planning on a real universe, run:"
echo "  python3 scripts/dx-ralph.py plan --universe <bd-epic-id>..."
