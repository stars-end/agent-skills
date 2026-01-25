#!/usr/bin/env bash
# dx-toolchain.sh
# Tooling + env consistency checks for canonical VMs.
#
# Modes:
#   dx-toolchain check         # local checks only
#   dx-toolchain ensure        # best-effort installs (idempotent)
#   dx-toolchain check --all   # run on all canonical VMs via SSH
#
# This script never prints secrets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

MODE="${1:-check}"
SHIFTED=0
ALL=0

if [[ "$MODE" == "check" || "$MODE" == "ensure" ]]; then
  SHIFTED=1
  shift || true
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) ALL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

want_version_gh="2.86.0"
want_version_railway="4.26.0"
want_version_op_min="2.18.0"
want_version_ru="1.2.1"

have() { command -v "$1" >/dev/null 2>&1; }

print_kv() { printf "%-12s %s\n" "$1" "$2"; }

check_local() {
  export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"

  echo "=== dx-toolchain ($(hostname -s 2>/dev/null || hostname)) ==="
  print_kv "os" "$(uname -s 2>/dev/null || echo unknown)"
  print_kv "agent-skills" "$(cd "$HOME/agent-skills" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo missing)"
  echo ""

  # Core tools
  for bin in git ssh curl; do
    if have "$bin"; then
      print_kv "$bin" "ok"
    else
      print_kv "$bin" "MISSING"
    fi
  done

  # mise
  if have mise; then
    print_kv "mise" "$(mise --version 2>/dev/null | head -1 || echo ok)"
  else
    print_kv "mise" "MISSING (recommended: standardize gh/railway/node)"
  fi

  # ru
  if have ru; then
    got="$(ru --version 2>/dev/null | awk '{print $NF}' || echo unknown)"
    print_kv "ru" "$got (want $want_version_ru)"
  else
    print_kv "ru" "MISSING (run: $HOME/agent-skills/scripts/install-ru.sh)"
  fi

  # bd
  if have bd; then
    print_kv "bd" "ok"
  else
    print_kv "bd" "MISSING"
  fi

  # cass (optional)
  if have cass; then
    print_kv "cass" "ok"
  else
    print_kv "cass" "missing (optional)"
  fi

  # gh
  if have gh; then
    got="$(gh --version 2>/dev/null | head -1 | awk '{print $3}' || echo unknown)"
    print_kv "gh" "$got (want $want_version_gh)"
  else
    print_kv "gh" "MISSING"
  fi

  # railway
  if have railway; then
    got="$(railway --version 2>/dev/null | awk '{print $NF}' || echo unknown)"
    print_kv "railway" "$got (want $want_version_railway)"
  else
    print_kv "railway" "MISSING"
  fi

  # op
  if have op; then
    got="$(op --version 2>/dev/null | sed -E 's/[^0-9.]*([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/' | head -1 || echo unknown)"
    print_kv "op" "$got (min $want_version_op_min)"
  else
    print_kv "op" "MISSING"
  fi

  # Node/npx (needed for Slack MCP npx flow)
  if have node; then
    print_kv "node" "$(node --version 2>/dev/null || echo ok)"
  else
    print_kv "node" "missing (needed for npx slack-mcp-server)"
  fi
  if have npx; then
    print_kv "npx" "ok"
  else
    print_kv "npx" "missing (comes with npm)"
  fi

  # Worktree tooling present?
  if [[ -x "$HOME/bin/worktree-setup.sh" ]]; then
    print_kv "worktree-setup" "ok ($HOME/bin/worktree-setup.sh)"
  else
    print_kv "worktree-setup" "missing (run: $HOME/agent-skills/scripts/dx-ensure-bins.sh)"
  fi
}

ensure_local() {
  export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
  "$HOME/agent-skills/scripts/ensure-shell-path.sh" >/dev/null 2>&1 || true
  "$HOME/agent-skills/scripts/dx-ensure-bins.sh" >/dev/null 2>&1 || true

  if ! have mise; then
    "$HOME/agent-skills/scripts/install-mise.sh" >/dev/null 2>&1 || true
  fi

  if ! have ru; then
    "$HOME/agent-skills/scripts/install-ru.sh" || true
  fi

  # Best-effort: standardize via mise if present (don’t hard-fail).
  if have mise; then
    mise use -g "railway@${want_version_railway}" >/dev/null 2>&1 || true
    mise use -g "gh@${want_version_gh}" >/dev/null 2>&1 || true
    mise install >/dev/null 2>&1 || true
  fi
}

run_all() {
  if ! declare -p CANONICAL_VMS >/dev/null 2>&1; then
    echo "canonical-targets not loaded; cannot --all" >&2
    exit 2
  fi

  local self_key
  self_key="${CANONICAL_HOST_KEY:-}"

  for entry in "${CANONICAL_VMS[@]}"; do
    target="${entry%%:*}"
    echo ""
    echo ">>> $target"

    target_host="${target#*@}"
    if [[ -n "$self_key" && "$target_host" == "$self_key" ]]; then
      "$HOME/agent-skills/scripts/dx-toolchain.sh" "${MODE}" || true
      continue
    fi

    ssh_canonical_vm "$target" "export PATH=\\\"\\$HOME/.local/share/mise/shims:\\$HOME/.local/share/mise/bin:\\$HOME/.local/bin:\\$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:\\$PATH\\\"; cd \\$HOME/agent-skills 2>/dev/null && git pull --ff-only origin master >/dev/null 2>&1 || true; ~/agent-skills/scripts/dx-toolchain.sh ${MODE} 2>/dev/null || ~/agent-skills/scripts/dx-toolchain.sh ${MODE} || true"
  done
}

if [[ "$ALL" == "1" ]]; then
  run_all
  exit 0
fi

case "$MODE" in
  check) check_local ;;
  ensure) ensure_local; check_local ;;
  *) echo "usage: dx-toolchain [check|ensure] [--all]" >&2; exit 2 ;;
esac
