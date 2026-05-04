#!/usr/bin/env bash
#
# dx-codex-session-repair-fleet-install.sh
#
# Roll out the Codex session repair tool and nightly cron to the supported
# canonical hosts.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOSTS_YAML="$REPO_ROOT/configs/fleet_hosts.yaml"

TARGETS="$(
  python3 - <<'PY' "$HOSTS_YAML"
import os
import sys
import yaml

path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(path, "r", encoding="utf-8"))["hosts"]
for name in ("macmini", "epyc12", "epyc6"):
    print(f"{name}|{hosts[name]['ssh']}")
PY
)"

while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  host="${row%%|*}"
  ssh_target="${row#*|}"
  echo "=== $host ($ssh_target) ==="
  ssh -n "$ssh_target" 'mkdir -p ~/agent-skills/lib ~/agent-skills/scripts ~/logs/dx ~/.dx-state/codex-session-repair'
  scp \
    "$REPO_ROOT/scripts/dx-codex-session-repair.py" \
    "$REPO_ROOT/scripts/dx-codex-session-repair.sh" \
    "$REPO_ROOT/scripts/dx-codex-session-repair-cron-install.sh" \
    "$ssh_target:~/agent-skills/scripts/"
  scp "$REPO_ROOT/lib/codex_session_repair.py" "$ssh_target:~/agent-skills/lib/codex_session_repair.py"
  ssh -n "$ssh_target" 'chmod +x ~/agent-skills/scripts/dx-codex-session-repair.py ~/agent-skills/scripts/dx-codex-session-repair.sh ~/agent-skills/scripts/dx-codex-session-repair-cron-install.sh && ~/agent-skills/scripts/dx-codex-session-repair-cron-install.sh'
done <<< "$TARGETS"
