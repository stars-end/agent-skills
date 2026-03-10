#!/usr/bin/env bash
#
# test-workspace-first-runtime.sh (bd-kuhj.3)
#
# Real runtime validation harness for the workspace-first contract.
# This script only delegates to tests with executable assertions.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ROOT="${AGENTS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

echo "=== bd-kuhj.3 Workspace-First Runtime Validation ==="
echo ""

echo "1. dx-batch workspace-first tests"
pytest -q "$SCRIPT_DIR/dx_batch/test_workspace_first.py"

echo ""
echo "2. cleanup protection tests"
bash "$SCRIPT_DIR/test-worktree-protection.sh"

echo ""
echo "=== Validation Complete ==="
