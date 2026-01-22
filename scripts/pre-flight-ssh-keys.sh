#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Pre-Flight SSH Keys Check"
echo "================================="
echo

SSH_DOCTOR="$HOME/agent-skills/ssh-key-doctor/check.sh"
if [ ! -x "$SSH_DOCTOR" ]; then
  echo "⚠️  ssh-key-doctor not installed (recommended)"
  echo "   Run: ~/agent-skills/ssh-key-doctor/check.sh"
  exit 0
fi

# Local-only is fast and safe; remote checks can be noisy if host keys aren't trusted yet.
echo "Running local-only SSH doctor..."
"$SSH_DOCTOR" --local-only

echo
echo "Remote reachability (optional):"
echo "  DX_SSH_DOCTOR_REMOTE=1 $SSH_DOCTOR --remote-only"
echo
echo "================================="
