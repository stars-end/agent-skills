#!/usr/bin/env bash
#
# Fleet Sync command family:
#   dx-fleet check
#   dx-fleet repair
#   dx-fleet audit --daily/--weekly
#
# Thin dispatch layer: real implementations live in script siblings.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  dx-fleet check [--mode daily|weekly] [--json]
  dx-fleet repair [--json]
  dx-fleet audit --daily|--weekly [--json] [--state-dir DIR]

Daily audit consumes Fleet Sync health artifacts.
Weekly audit is governance/compliance-heavy.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  check)
    exec "$SCRIPT_DIR/dx-fleet-check.sh" "$@"
    ;;
  repair)
    exec "$SCRIPT_DIR/dx-fleet-repair.sh" "$@"
    ;;
  audit)
    exec "$SCRIPT_DIR/dx-audit.sh" "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown subcommand: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac
