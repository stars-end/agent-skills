#!/usr/bin/env bash
#
# Deprecated wrapper kept for backward compatibility.
# Canonical daily entrypoint is dx-audit-cron.sh --daily.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/dx-audit-cron.sh" --daily "$@"
