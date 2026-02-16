#!/usr/bin/env bash
set -euo pipefail

# dx-codex-skills-install.sh
#
# Backwards-compatible wrapper for dx-agents-skills-install.sh.
# This script name is kept for backwards compatibility.
#
# IMPORTANT: Skills are ALWAYS linked from ~/agent-skills (canonical),
# never /tmp/agents/. See dx-agents-skills-install.sh for details.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to the main installer
exec "$SCRIPT_DIR/dx-agents-skills-install.sh" "$@"
