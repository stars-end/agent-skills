#!/usr/bin/env bash
#
# dx-fleet-check.sh
#
# V7.8 Fleet-wide read-only status check.
# Runs dx-verify-clean + dx-status on all VMs and prints a short report.
#
# MUST NOT mutate anything on remotes.
# SSH failures print warnings and continue.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../configs/fleet_hosts.yaml"

if [[ ! -f "$CONFIG" ]]; then
  echo "❌ Fleet config not found: $CONFIG"
  exit 1
fi

echo "🔍 DX Fleet Check (V7.8)"
echo ""

# Parse hosts from YAML (simple grep/sed approach)
parse_hosts() {
  grep "^  .*:$" "$CONFIG" | grep -v "canonical_repos:" | sed 's/^  //;s/:.*//'
}

# Get ssh target for a host
get_ssh_target() {
  local host="$1"
  grep -A 5 "^  $host:" "$CONFIG" | grep "ssh:" | sed 's/.*"\(.*\)".*/\1/'
}

# Check a remote host via SSH
check_remote_host() {
  local host="$1"
  local ssh_target

  ssh_target=$(get_ssh_target "$host")
  if [[ -z "$ssh_target" ]]; then
    echo "  ❌ No SSH target configured for $host"
    return 1
  fi

  echo "📡 $host ($ssh_target)"

  # Run read-only checks via SSH
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" "
    export BEADS_DIR=\"\$HOME/bd/.beads\"

    echo '  Canonical hygiene:'
    for repo in agent-skills prime-radiant-ai affordabot llm-common; do
      repo_path=\"\$HOME/\$repo\"
      if [[ -d \"\$repo_path/.git\" ]]; then
        branch=\$(git -C \"\$repo_path\" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
        status=\$(git -C \"\$repo_path\" status --porcelain=v1 2>/dev/null || true)
        stash_count=\$(git -C \"\$repo_path\" stash list 2>/dev/null | wc -l | tr -d ' ')

        if [[ -n \"\$status\" ]] || [[ \"\$stash_count\" -gt 0 ]]; then
          echo \"    ❌ \$repo: branch=\$branch dirty=\$([ -n \"\$status\" ] && echo 'yes' || echo 'no') stashes=\$stash_count\"
        else
          echo \"    ✅ \$repo: branch=\$branch clean\"
        fi
      else
        echo \"    ⚠️  \$repo: not found\"
      fi
    done

    echo ''
    echo '  DX verify-clean:'
    if [[ -x \"\$HOME/agent-skills/scripts/dx-verify-clean.sh\" ]]; then
      if \"\$HOME/agent-skills/scripts/dx-verify-clean.sh\" >/dev/null 2>&1; then
        echo '    ✅ PASS'
      else
        echo '    ❌ FAIL'
      fi
    else
      echo '    ⚠️  script not found'
    fi

    echo ''
    echo '  DX status (last 10 lines):'
    if [[ -x \"\$HOME/agent-skills/scripts/dx-status.sh\" ]]; then
      \"\$HOME/agent-skills/scripts/dx-status.sh\" 2>/dev/null | tail -10 | sed 's/^/    /' || echo '    (no output)'
    else
      echo '    script not found'
    fi
  " 2>/dev/null; then
    return 0
  else
    echo "  ⚠️  SSH failed or host unreachable"
    return 1
  fi
}

# Check local host (we are currently on it)
check_local_host() {
  local host="$1"
  echo "💻 $host (local)"

  echo "  Canonical hygiene:"
  for repo in agent-skills prime-radiant-ai affordabot llm-common; do
    repo_path="$HOME/$repo"
    if [[ -d "$repo_path/.git" ]]; then
      branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
      status=$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)
      stash_count=$(git -C "$repo_path" stash list 2>/dev/null | wc -l | tr -d ' ')

      if [[ -n "$status" ]] || [[ "$stash_count" -gt 0 ]]; then
        echo "    ❌ $repo: branch=$branch dirty=$([ -n "$status" ] && echo 'yes' || echo 'no') stashes=$stash_count"
      else
        echo "    ✅ $repo: branch=$branch clean"
      fi
    else
      echo "    ⚠️  $repo: not found"
    fi
  done

  echo ""
  echo "  DX verify-clean:"
  if [[ -x "$HOME/agent-skills/scripts/dx-verify-clean.sh" ]]; then
    if "$HOME/agent-skills/scripts/dx-verify-clean.sh" >/dev/null 2>&1; then
      echo "    ✅ PASS"
    else
      echo "    ❌ FAIL"
    fi
  else
    echo "    ⚠️  script not found"
  fi

  echo ""
  echo "  DX status (last 10 lines):"
  if [[ -x "$HOME/agent-skills/scripts/dx-status.sh" ]]; then
    "$HOME/agent-skills/scripts/dx-status.sh" 2>/dev/null | tail -10 | sed 's/^/    /' || echo "    (no output)"
  else
    echo "    script not found"
  fi
}

# Get current hostname to determine which host is local
CURRENT_HOST=$(hostname -s 2>/dev/null | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')

# Map possible hostname variations
LOCAL_HOST="unknown"
if [[ "$CURRENT_HOST" =~ macmini ]] || [[ "$CURRENT_HOST" =~ mac-mini ]]; then
  LOCAL_HOST="macmini"
elif [[ "$CURRENT_HOST" =~ homedesktop ]]; then
  LOCAL_HOST="homedesktop-wsl"
elif [[ "$CURRENT_HOST" =~ epyc ]]; then
  LOCAL_HOST="epyc6"
fi

# Check all hosts
for host in $(parse_hosts); do
  echo "----------------------------------------"
  if [[ "$host" == "$LOCAL_HOST" ]]; then
    check_local_host "$host"
  else
    check_remote_host "$host"
  fi
  echo ""
done

echo "========================================"
echo "✅ Fleet check complete"
