#!/usr/bin/env bash
# dx-triage-cron.sh
# Cron job that checks repo health and sets blockers for drifted repos.
#
# Run via cron every 4 hours:
#   0 */4 * * * ~/agent-skills/scripts/dx-triage-cron.sh >> ~/logs/dx-triage-cron.log 2>&1
#
# What it does:
# 1. Checks each canonical repo
# 2. If repo is in "bad state" (wrong branch + stale), writes .git/DX_BLOCKED
# 3. Pre-commit hook (installed by dx-hydrate) checks for this file
# 4. Agent is forced to run dx-triage --fix before committing
#
# "Bad state" criteria:
# - On non-trunk branch AND
# - No commits in last 24 hours (abandoned feature work)
# OR
# - Behind origin by > 100 commits (severely stale)

set -euo pipefail

# Resolve symlinks to get actual script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

CANONICAL_TRUNK_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"
STALE_HOURS="${DX_TRIAGE_STALE_HOURS:-24}"
STALE_COMMITS="${DX_TRIAGE_STALE_COMMITS:-100}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Collect all repos to check
ALL_REPOS=()
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}")
fi
if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}")
fi

if [[ ${#ALL_REPOS[@]} -eq 0 ]]; then
    log "No canonical repos defined, exiting"
    exit 0
fi

log "dx-triage-cron starting on $(hostname -s 2>/dev/null || hostname)"

for repo in "${ALL_REPOS[@]}"; do
    repo_path="$HOME/$repo"
    blocker_file="$repo_path/.git/DX_BLOCKED"

    if [[ ! -d "$repo_path/.git" ]]; then
        continue
    fi

    cd "$repo_path"

    # Get current branch
    branch="$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

    # Check if on trunk
    on_trunk=0
    if [[ "$branch" == "$CANONICAL_TRUNK_BRANCH" || "$branch" == "main" ]]; then
        on_trunk=1
    fi

    # Check staleness (commits behind origin/trunk)
    git fetch origin --quiet 2>/dev/null || true
    behind=0
    if git rev-parse --verify "origin/$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
        behind=$(git rev-list --count "HEAD..origin/$CANONICAL_TRUNK_BRANCH" 2>/dev/null || echo 0)
    fi

    # Check last commit time (in hours)
    last_commit_ts=$(git log -1 --format=%ct 2>/dev/null || echo 0)
    current_ts=$(date +%s)
    hours_since_commit=$(( (current_ts - last_commit_ts) / 3600 ))

    # Determine if repo should be blocked
    should_block=0
    block_reason=""

    # Criteria 1: On feature branch + no recent commits (abandoned work)
    if [[ "$on_trunk" -eq 0 && "$hours_since_commit" -ge "$STALE_HOURS" ]]; then
        should_block=1
        block_reason="On branch '$branch' with no commits for ${hours_since_commit}h (threshold: ${STALE_HOURS}h)"
    fi

    # Criteria 2: Severely behind origin (even if on trunk)
    if [[ "$behind" -ge "$STALE_COMMITS" ]]; then
        should_block=1
        block_reason="$behind commits behind origin/$CANONICAL_TRUNK_BRANCH (threshold: $STALE_COMMITS)"
    fi

    # Apply or clear blocker
    if [[ "$should_block" -eq 1 ]]; then
        if [[ ! -f "$blocker_file" ]]; then
            log "$repo: BLOCKING - $block_reason"
            cat > "$blocker_file" <<EOF
DX_BLOCKED: This repo needs attention before you can commit.

Reason: $block_reason

To unblock, run:
  dx-triage --fix

Or manually fix and remove this file:
  rm $blocker_file

Blocked at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF
        else
            log "$repo: still blocked - $block_reason"
        fi
    else
        if [[ -f "$blocker_file" ]]; then
            log "$repo: UNBLOCKING - repo is healthy"
            rm -f "$blocker_file"
        fi
    fi
done

log "dx-triage-cron complete"
