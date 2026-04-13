#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
DEPRECATED: pre-flight-gh-cli.sh is no longer a canonical fresh-device check.

Use:
  scripts/dx-check.sh

For manual local verification:
  gh --version
  gh auth status
EOF
exit 2
