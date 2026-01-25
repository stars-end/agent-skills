#!/usr/bin/env bash
# dx-fleet-status.sh
# Tech-lead dashboard: show drift + readiness across canonical VMs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

if ! declare -p CANONICAL_VMS >/dev/null 2>&1; then
  echo "Error: canonical-targets unavailable" >&2
  exit 2
fi

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"

echo "=== dx-fleet-status ($(date -u '+%Y-%m-%dT%H:%MZ')) ==="
echo "local: $(hostname -s 2>/dev/null || hostname)"

SELF_KEY="${CANONICAL_HOST_KEY:-}"

for entry in "${CANONICAL_VMS[@]}"; do
  target="${entry%%:*}"
  os="${entry#*:}"; os="${os%%:*}"
  echo ""
  echo "--- $target ($os) ---"

  target_host="${target#*@}"
  if [[ -n "$SELF_KEY" && "$target_host" == "$SELF_KEY" ]]; then
    {
      export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
      echo "host: $(hostname -s 2>/dev/null || hostname)"
      echo "agent-skills: $(cd ~/agent-skills 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo missing)"
      echo ""
      echo "[dx-status]"
      ~/agent-skills/scripts/dx-status.sh 2>/dev/null || true
      echo ""
      echo "[dx-toolchain]"
      ~/agent-skills/scripts/dx-toolchain.sh check 2>/dev/null || true
    } | sed -e 's/\x1b\[[0-9;]*m//g'
  else
    ssh_canonical_vm "$target" 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH";
      cd "$HOME/agent-skills" 2>/dev/null && git pull --ff-only origin master >/dev/null 2>&1 || true;
      echo "host: $(hostname -s 2>/dev/null || hostname)";
      echo "agent-skills: $(cd ~/agent-skills 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo missing)";
      echo "";
      echo "[dx-status]";
      ~/agent-skills/scripts/dx-status.sh 2>/dev/null || true;
      echo "";
      echo "[dx-toolchain]";
      ~/agent-skills/scripts/dx-toolchain.sh check 2>/dev/null || true;
    ' | sed -e 's/\x1b\[[0-9;]*m//g'
  fi
done

echo ""
echo "=== end ==="
