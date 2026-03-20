#!/usr/bin/env bash
set -euo pipefail

# dx-codex-skills-install.sh
#
# Install canonical shared skills into Codex's user skills plane.
#
# IMPORTANT: Skills are ALWAYS linked from ~/agent-skills (canonical),
# never /tmp/agents/. See dx-agents-skills-install.sh for details.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to the main installer with the Codex user-scope destination.
DEST_DIR="${DEST_DIR:-$HOME/.codex/skills}" \
  exec "$SCRIPT_DIR/dx-agents-skills-install.sh" "$@"
