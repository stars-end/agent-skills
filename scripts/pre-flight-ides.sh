#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
DEPRECATED: pre-flight-ides.sh is no longer canonical.

Use:
  scripts/dx-check.sh
  health/mcp-doctor/check.sh

Those surfaces validate active MCP/runtime contract instead of legacy IDE inventory loops.
EOF
exit 2
