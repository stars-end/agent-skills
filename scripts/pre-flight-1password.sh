#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
DEPRECATED: pre-flight-1password.sh is removed from the canonical bootstrap path.

Use agent-safe auth checks instead:
  scripts/dx-bootstrap-auth.sh --json
  scripts/dx-op-auth-status.sh --json

For human macOS recovery (not agent/cron auth), see:
  core/op-secrets-quickref/SKILL.md
EOF
exit 2
