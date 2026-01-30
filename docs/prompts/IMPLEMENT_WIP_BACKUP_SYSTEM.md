# Implementation Prompt: WIP Backup System

**Issue:** `agent-skills-fd9`
**Priority:** P1

---

## Problem Statement

auto-checkpoint creates local commits but push failures are silent. This creates "unknown divergence debt" - you don't know if a stale VM has recoverable work or not.

**Current failure mode:**
```
homedesktop-wsl: 1 local commit (48h old, push failed silently)
epyc6: 15 commits pushed
Result: branches diverged, user confused on return
```

---

## Design Principles

1. **Never destructive by default** - no auto-reset without remote backup
2. **Always recoverable** - WIP refs are remote, accessible from any VM
3. **Zero cognitive load** - tools find WIP, user doesn't manage refs
4. **No branch explosion** - single moving ref per (host, repo, branch)

---

## Architecture

### WIP Ref Naming

```
refs/heads/wip/<hostname>/<branch>

Examples:
  wip/macmini/master
  wip/epyc6/feature-plaid
  wip/homedesktop-wsl/fix-auth
```

**Key:** One ref per (host, branch), updated in place with `--force-with-lease`.

### Index File

```
refs/heads/dx/index:.dx/wip-index.json

{
  "repo": "agent-skills",
  "updated": 1738260000,
  "hosts": {
    "macmini": {
      "sha": "abc123",
      "branch": "feature-a",
      "ts": 1738260000,
      "message": "auto-checkpoint: add plaid tests"
    },
    "epyc6": {
      "sha": "def456",
      "branch": "master",
      "ts": 1738257000,
      "message": "auto-checkpoint: fix auth bug"
    }
  }
}
```

---

## Implementation Tasks

### Task 1: Modify auto-checkpoint.sh

**File:** `~/agent-skills/scripts/auto-checkpoint.sh`

**Changes:**

```bash
#!/bin/bash
# auto-checkpoint.sh (revised)

HOST="$(hostname -s)"

checkpoint_repo() {
    local repo="$1"
    cd "$repo" || return 1

    # 1. Skip if no changes
    if git diff --quiet && git diff --cached --quiet; then
        log "No changes in $repo"
        return 0
    fi

    # 2. Stage and commit
    git add -A
    local commit_msg="auto-checkpoint: $(date '+%Y-%m-%d %H:%M:%S')"
    git commit -m "$commit_msg" || {
        log "Commit failed in $repo"
        return 1
    }

    local branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'detached')"
    local sha="$(git rev-parse HEAD)"

    # 3. Try push to real branch (nice-to-have)
    if git push origin "$branch" 2>/dev/null; then
        log "Pushed to origin/$branch"
    else
        log "Push to origin/$branch failed (will use WIP backup)"
    fi

    # 4. ALWAYS push to WIP namespace (must-have)
    local wip_ref="refs/heads/wip/${HOST}/${branch}"
    if git push origin "HEAD:${wip_ref}" --force-with-lease 2>/dev/null; then
        log "WIP backup: origin/${wip_ref}"

        # 5. Update index
        update_wip_index "$repo" "$branch" "$sha" "$commit_msg"
    else
        log "ERROR: WIP backup push failed for $repo"
        # This is a real problem - alert
        notify_wip_failure "$repo" "$branch"
    fi
}

update_wip_index() {
    local repo="$1"
    local branch="$2"
    local sha="$3"
    local message="$4"
    local ts="$(date +%s)"

    # Fetch current index
    git fetch origin refs/heads/dx/index:refs/remotes/origin/dx/index 2>/dev/null || true

    # Create/update index file
    local index_file=".dx/wip-index.json"
    mkdir -p .dx

    if git show origin/dx/index:${index_file} > "$index_file" 2>/dev/null; then
        # Update existing
        python3 - "$index_file" "$HOST" "$branch" "$sha" "$ts" "$message" << 'PYEOF'
import sys, json
path, host, branch, sha, ts, msg = sys.argv[1:7]
try:
    with open(path) as f:
        data = json.load(f)
except:
    data = {"repo": "", "hosts": {}}

data["updated"] = int(ts)
data["hosts"][host] = {"sha": sha, "branch": branch, "ts": int(ts), "message": msg}

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
    else
        # Create new
        cat > "$index_file" << EOF
{
  "repo": "$(basename "$repo")",
  "updated": $ts,
  "hosts": {
    "$HOST": {"sha": "$sha", "branch": "$branch", "ts": $ts, "message": "$message"}
  }
}
EOF
    fi

    # Commit and push index
    git add "$index_file"
    git commit -m "dx: update wip-index for $HOST" --allow-empty 2>/dev/null || true
    git push origin HEAD:refs/heads/dx/index --force-with-lease 2>/dev/null || true
}

notify_wip_failure() {
    local repo="$1"
    local branch="$2"
    # TODO: Slack notification
    log "CRITICAL: WIP backup failed for $repo on $branch"
}
```

### Task 2: Modify ru sync behavior

**Create:** `~/agent-skills/scripts/ru-sync-wrapper.sh` (or modify ru config)

```bash
#!/bin/bash
# ru-sync-wrapper.sh
# Fetch-only for active VMs, full sync for reference VMs

get_vm_role() {
    if [ -f ~/.dx-vm-role ]; then
        cat ~/.dx-vm-role
    elif [ -f .dx/repo-role ]; then
        cat .dx/repo-role
    else
        echo "active"  # Default to safe behavior
    fi
}

sync_repo() {
    local repo="$1"
    cd "$repo" || return 1

    local role="$(get_vm_role)"

    case "$role" in
        reference)
            log "Reference mode: hard reset to origin"
            git fetch origin --prune
            local default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo 'master')"
            git checkout -q "$default_branch" 2>/dev/null || true
            git reset --hard "origin/$default_branch"
            ;;
        active|*)
            log "Active mode: fetch only"
            git fetch origin --prune
            # NEVER pull - user/agent decides when to integrate
            ;;
    esac
}
```

### Task 3: Create dx-restore command

**File:** `~/agent-skills/scripts/dx-restore.sh`

```bash
#!/bin/bash
# dx-restore.sh
# Restore WIP from any host

set -e

REPO="${1:-.}"
cd "$REPO"

# Fetch index
git fetch origin refs/heads/dx/index:refs/remotes/origin/dx/index 2>/dev/null || {
    echo "No WIP index found for this repo"
    exit 1
}

# Read index
INDEX=$(git show origin/dx/index:.dx/wip-index.json 2>/dev/null)
if [ -z "$INDEX" ]; then
    echo "No WIP index found"
    exit 1
fi

echo "=== WIP Backups ==="
echo "$INDEX" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
hosts = data.get('hosts', {})

if not hosts:
    print('No WIP backups found')
    sys.exit(0)

# Sort by timestamp, newest first
sorted_hosts = sorted(hosts.items(), key=lambda x: x[1].get('ts', 0), reverse=True)

for i, (host, info) in enumerate(sorted_hosts, 1):
    ts = datetime.fromtimestamp(info.get('ts', 0)).strftime('%Y-%m-%d %H:%M')
    branch = info.get('branch', 'unknown')
    sha = info.get('sha', 'unknown')[:8]
    msg = info.get('message', '')[:40]
    print(f'{i}. {host}/{branch} ({ts}) - {sha} - {msg}')
"

echo ""
read -p "Restore which? [1/2/...] or 'q' to quit: " choice

if [ "$choice" = "q" ]; then
    exit 0
fi

# Get host/branch from choice
RESTORE_INFO=$(echo "$INDEX" | python3 -c "
import sys, json
data = json.load(sys.stdin)
hosts = data.get('hosts', {})
sorted_hosts = sorted(hosts.items(), key=lambda x: x[1].get('ts', 0), reverse=True)
choice = int('${choice}') - 1
if 0 <= choice < len(sorted_hosts):
    host, info = sorted_hosts[choice]
    print(f\"{host} {info['branch']} {info['sha']}\")
")

HOST=$(echo "$RESTORE_INFO" | cut -d' ' -f1)
BRANCH=$(echo "$RESTORE_INFO" | cut -d' ' -f2)
SHA=$(echo "$RESTORE_INFO" | cut -d' ' -f3)

# Fetch WIP ref
WIP_REF="wip/${HOST}/${BRANCH}"
git fetch origin "refs/heads/${WIP_REF}:refs/remotes/origin/${WIP_REF}" 2>/dev/null || {
    echo "Could not fetch WIP ref: $WIP_REF"
    exit 1
}

# Create rescue branch
RESCUE_BRANCH="rescue/${HOST}/${BRANCH}"
git checkout -b "$RESCUE_BRANCH" "origin/${WIP_REF}"

echo ""
echo "✅ Restored to branch: $RESCUE_BRANCH"
echo "   From: origin/${WIP_REF}"
echo "   SHA: $SHA"
```

### Task 4: Update dx-triage to show WIP status

**Modify:** `~/agent-skills/scripts/dx-triage.sh`

Add section that reads WIP index and shows:
- Which hosts have WIP backups
- How old they are
- Whether current VM is diverged with WIP available

```bash
# Add to dx-triage output:

show_wip_status() {
    local repo="$1"
    cd "$repo" || return

    git fetch origin refs/heads/dx/index:refs/remotes/origin/dx/index 2>/dev/null || return

    local index=$(git show origin/dx/index:.dx/wip-index.json 2>/dev/null)
    [ -z "$index" ] && return

    echo ""
    echo "WIP Backups:"
    echo "$index" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
for host, info in data.get('hosts', {}).items():
    ts = datetime.fromtimestamp(info.get('ts', 0))
    age = (datetime.now() - ts).total_seconds() / 3600
    branch = info.get('branch', '?')
    print(f'  {host}/{branch}: {age:.0f}h ago')
"
}
```

### Task 5: Create VM role management

**File:** `~/agent-skills/scripts/dx-role.sh`

```bash
#!/bin/bash
# dx-role.sh
# Manage VM role: active vs reference

ROLE_FILE="$HOME/.dx-vm-role"

case "${1:-}" in
    active)
        echo "active" > "$ROLE_FILE"
        echo "✅ VM role set to: active"
        echo "   auto-checkpoint: enabled"
        echo "   ru sync: fetch only"
        ;;
    reference)
        echo "reference" > "$ROLE_FILE"
        echo "✅ VM role set to: reference"
        echo "   auto-checkpoint: disabled"
        echo "   ru sync: hard reset to origin"
        ;;
    ""|status)
        if [ -f "$ROLE_FILE" ]; then
            echo "VM role: $(cat "$ROLE_FILE")"
        else
            echo "VM role: active (default)"
        fi
        ;;
    *)
        echo "Usage: dx-role [active|reference|status]"
        exit 1
        ;;
esac
```

---

## Testing

### Test 1: WIP backup on push failure

```bash
# Simulate push failure
cd ~/agent-skills
echo "test" >> test-file.txt
# Block real push somehow (e.g., make branch protected)
# Run auto-checkpoint
auto-checkpoint

# Verify WIP ref exists
git ls-remote origin 'refs/heads/wip/*'
```

### Test 2: Restore from another VM

```bash
# On VM A: make changes, auto-checkpoint
# On VM B:
dx-restore ~/agent-skills
# Should show VM A's WIP and offer to restore
```

### Test 3: Reference mode sync

```bash
dx-role reference
# Make local changes
echo "junk" >> file.txt
# Run sync
ru sync
# Local changes should be wiped, repo reset to origin
```

---

## Cleanup / Retention (Future)

Add periodic cleanup of old WIP refs:

```bash
# Keep only WIP refs updated in last 30 days
git for-each-ref --format='%(refname) %(committerdate:unix)' refs/heads/wip/ | \
while read ref ts; do
    age_days=$(( ($(date +%s) - ts) / 86400 ))
    if [ "$age_days" -gt 30 ]; then
        git push origin --delete "${ref#refs/heads/}"
    fi
done
```

---

## Completion

```bash
bd update agent-skills-fd9 --status closed --reason "WIP backup system implemented"
bd sync
```
