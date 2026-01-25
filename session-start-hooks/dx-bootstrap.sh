#!/usr/bin/env bash
#
# Cross-agent SessionStart Hook: DX Bootstrap
#
# Canonical entrypoint for session-start bootstrap across IDEs.
# Kept as a thin wrapper to preserve backwards compatibility with older docs/tools.
#
set -euo pipefail

exec "$(dirname "$0")/claude-code-dx-bootstrap.sh"

