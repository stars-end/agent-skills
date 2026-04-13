#!/usr/bin/env bash
#
# dx-bootstrap-device.sh
#
# Canonical fresh-device bootstrap entrypoint (role-aware, conservative).
# This script delegates to existing primitives rather than duplicating setup
# logic. In check-only mode, it skips role-specific install steps such as cron.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROLE="${DX_BOOTSTRAP_ROLE:-auto}"
CHECK_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  scripts/dx-bootstrap-device.sh [--role auto|macos-client|linux-spoke|hub-controller] [--check-only]

Role policy:
  - macos-client: local developer Mac (spoke behavior)
  - linux-spoke: non-hub Linux canonical VM
  - hub-controller: hub/controller host (epyc12 or DX_CONTROLLER=1)
  - auto: detect from host/OS

This entrypoint does not retrieve secrets directly and does not perform
destructive cleanup. It delegates to canonical primitives.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      ROLE="${2:-}"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

detect_role() {
  if [[ "$ROLE" != "auto" ]]; then
    echo "$ROLE"
    return
  fi

  local host os
  host="$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  os="$(uname -s)"

  if [[ "${DX_CONTROLLER:-0}" == "1" || "$host" == "epyc12" ]]; then
    echo "hub-controller"
    return
  fi

  if [[ "$os" == "Darwin" ]]; then
    echo "macos-client"
  else
    echo "linux-spoke"
  fi
}

run_step() {
  local label="$1"
  shift
  echo "-> ${label}"
  if "$@"; then
    echo "   ok"
  else
    echo "   warn: ${label} failed; continuing" >&2
    failures=$((failures + 1))
  fi
}

run_if_executable() {
  local path="$1"
  shift
  if [[ -x "$path" ]]; then
    run_step "$path $*" "$path" "$@"
  else
    echo "-> warn: missing executable $path" >&2
  fi
}

resolved_role="$(detect_role)"
case "$resolved_role" in
  macos-client|linux-spoke|hub-controller)
    ;;
  *)
    echo "Invalid role: $resolved_role" >&2
    exit 2
    ;;
esac

echo "DX bootstrap role: $resolved_role"
if [[ "$CHECK_ONLY" == "1" ]]; then
  echo "Mode: check-only (no role-specific cron install)"
fi

failures=0

run_if_executable "${AGENTS_ROOT}/scripts/ensure-shell-path.sh"
run_if_executable "${AGENTS_ROOT}/scripts/dx-ensure-bins.sh"
run_if_executable "${AGENTS_ROOT}/scripts/dx-bootstrap-auth.sh" --json

if [[ "$resolved_role" == "linux-spoke" ]]; then
  run_if_executable "${AGENTS_ROOT}/infra/vm-bootstrap/check.sh"
fi

if [[ "$CHECK_ONLY" != "1" ]]; then
  case "$resolved_role" in
    macos-client|linux-spoke)
      run_if_executable "${AGENTS_ROOT}/scripts/dx-spoke-cron-install.sh"
      ;;
    hub-controller)
      echo "-> hub-controller: spoke cron install skipped by design"
      ;;
  esac
fi

run_if_executable "${AGENTS_ROOT}/scripts/dx-check.sh"
run_if_executable "${AGENTS_ROOT}/health/mcp-doctor/check.sh"

if [[ "$failures" -gt 0 ]]; then
  echo "DX bootstrap completed with ${failures} warning/failure(s)." >&2
  exit 1
fi

echo "DX bootstrap complete."
