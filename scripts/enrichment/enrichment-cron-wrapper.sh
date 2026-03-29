#!/usr/bin/env bash
# enrichment-cron-wrapper.sh — Cron-safe launcher for nightly enrichment
#
# Uses cached OP resolution (dx_auth_load_zai_api_key) so cron does not
# hit 1Password on every invocation.  Falls back gracefully if the
# cache is cold or the service account is unavailable.
#
# Usage (cron):
#   0 3 * * * /path/to/agent-skills/scripts/enrichment/enrichment-cron-wrapper.sh >> /tmp/enrichment.log 2>&1
#
# Usage (interactive):
#   scripts/enrichment/enrichment-cron-wrapper.sh [--dry-run]

set -euo pipefail

export DX_AUTH_UNATTENDED_OP=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib/dx-auth.sh"

if ! dx_auth_load_zai_api_key; then
  echo "[enrichment] BLOCKED: failed to resolve ZAI_API_KEY from cache or 1Password" >&2
  exit 1
fi

exec python3 "${SCRIPT_DIR}/nightly-enrichment.py" "$@"
