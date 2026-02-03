#!/usr/bin/env bash
# Shim for health tools expecting canonical target registry here.
# Source of truth lives at: scripts/canonical-targets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/canonical-targets.sh"
