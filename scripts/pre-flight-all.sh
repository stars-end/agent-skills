#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<'EOF'
DEPRECATED: pre-flight-all.sh (V4.2.1) is no longer the canonical bootstrap surface.

Use the role-aware bootstrap/check flow instead:
  1) scripts/dx-bootstrap-device.sh --role auto --check-only
  2) scripts/dx-check.sh
  3) health/mcp-doctor/check.sh

Optional compatibility probes still available:
  - scripts/pre-flight-network.sh
  - scripts/pre-flight-ssh-keys.sh
  - scripts/pre-flight-railway.sh
EOF

if [[ -x "$SCRIPT_DIR/dx-bootstrap-device.sh" ]]; then
  echo
  echo "Running role-aware check-only bootstrap now..."
  exec "$SCRIPT_DIR/dx-bootstrap-device.sh" --role auto --check-only
fi

echo "Missing canonical bootstrap script: scripts/dx-bootstrap-device.sh" >&2
exit 2
