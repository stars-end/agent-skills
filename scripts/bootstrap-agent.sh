#!/usr/bin/env bash
# Legacy bootstrap shim.
# Canonical fresh-device entrypoint is scripts/dx-bootstrap-device.sh.

set -euo pipefail

echo "DEPRECATED: bootstrap-agent.sh is now a compatibility shim."
echo "Using canonical role-aware bootstrap entrypoint: scripts/dx-bootstrap-device.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/dx-bootstrap-device.sh"

if [[ ! -x "$BOOTSTRAP_SCRIPT" ]]; then
  echo "Missing canonical bootstrap script: $BOOTSTRAP_SCRIPT" >&2
  echo "Clone or update agent-skills, then run:" >&2
  echo "  ~/agent-skills/scripts/dx-bootstrap-device.sh --role auto" >&2
  exit 2
fi

exec "$BOOTSTRAP_SCRIPT" --role auto "$@"
