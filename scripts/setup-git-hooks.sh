#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "DEPRECATED: setup-git-hooks.sh no longer installs legacy V5 hooks."
echo "Using canonical hook bootstrap: scripts/dx-git-hooks-bootstrap.sh"

if [[ ! -x "$SCRIPT_DIR/dx-git-hooks-bootstrap.sh" ]]; then
    echo "Missing canonical hook bootstrap script: $SCRIPT_DIR/dx-git-hooks-bootstrap.sh" >&2
    exit 2
fi

exec "$SCRIPT_DIR/dx-git-hooks-bootstrap.sh" "$@"
