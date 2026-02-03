#!/usr/bin/env bash
# dx-wip-check.sh
# Check for stranded work branches (auto-checkpoint + wip)
# Run as part of dx-check

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo "=== Stranded Work (Auto-Checkpoint + WIP Branches) ==="

# dx-check can be run from anywhere. If we're not in a git repo, skip cleanly.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    info "Not in a git repository; skipping WIP branch check"
    exit 0
fi

# Determine trunk branch (prefer origin/HEAD; fall back to master).
CANONICAL_TRUNK_BRANCH="${CANONICAL_TRUNK_BRANCH:-}"
if [[ -z "$CANONICAL_TRUNK_BRANCH" ]]; then
    origin_head="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [[ -n "$origin_head" ]]; then
        CANONICAL_TRUNK_BRANCH="${origin_head##*/}"
    else
        CANONICAL_TRUNK_BRANCH="master"
    fi
fi

TRUNK_REF="origin/${CANONICAL_TRUNK_BRANCH}"
if ! git show-ref --verify --quiet "refs/remotes/${TRUNK_REF}" 2>/dev/null; then
    TRUNK_REF="${CANONICAL_TRUNK_BRANCH}"
fi

# Stashes are a common “where did my work go?” source (especially in canonical clones).
stash_count="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${stash_count:-0}" != "0" ]]; then
    warn "Local stashes present: $stash_count"
    echo "  Tip: stashes are not durable across VMs. Prefer: commit + push + PR."
fi

# Find candidate branch refs (local + origin/*). grep exits 1 on no matches; avoid failing dx-check in clean repos.
all_refs="$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null | sort -u)"

LOCAL_WIP="$(printf '%s\n' "$all_refs" | grep -E '^(wip/auto/|auto-checkpoint/)' || true)"
REMOTE_WIP="$(printf '%s\n' "$all_refs" | grep -E '^(origin/wip/auto/|origin/auto-checkpoint/)' || true)"

# Prefer local refs when present; only include remote ref if local counterpart is absent.
WIP_REFS=""
if [[ -n "$LOCAL_WIP" ]]; then
    WIP_REFS+="$LOCAL_WIP"$'\n'
fi
if [[ -n "$REMOTE_WIP" ]]; then
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        local_name="${ref#origin/}"
        if [[ -n "$LOCAL_WIP" ]] && printf '%s\n' "$LOCAL_WIP" | grep -qx "$local_name"; then
            continue
        fi
        WIP_REFS+="$ref"$'\n'
    done <<< "$REMOTE_WIP"
fi

WIP_REFS="$(printf '%s' "$WIP_REFS" | sed '/^$/d' | sort -u)"

if [[ -z "$WIP_REFS" ]]; then
    info "No auto-checkpoint/* or wip/auto/* branches found"
    exit 0
fi

FOUND_UNMERGED=0

while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue

    # List commits on this ref not in trunk.
    BRANCH_COMMITS="$(git log --oneline "${TRUNK_REF}..${ref}" 2>/dev/null || true)"

    if [[ -n "$BRANCH_COMMITS" ]]; then
        warn "Stranded commits: ${ref} (not in ${TRUNK_REF})"
        echo "$BRANCH_COMMITS" | head -3 | sed 's/^/  /'

        # If this is a local branch, show divergence from origin counterpart.
        if [[ "$ref" != origin/* ]]; then
            if git show-ref --verify --quiet "refs/remotes/origin/${ref}" 2>/dev/null; then
                lr="$(git rev-list --left-right --count "origin/${ref}...${ref}" 2>/dev/null || true)"
                behind="$(echo "$lr" | awk '{print $1}')"
                ahead="$(echo "$lr" | awk '{print $2}')"
                if [[ "${behind:-0}" != "0" || "${ahead:-0}" != "0" ]]; then
                    warn "  Diverged from origin/${ref}: ahead=${ahead:-0} behind=${behind:-0}"
                    echo "  Fix: git -C <repo> switch ${ref} && git pull --rebase (then push) OR open PR"
                fi
            else
                warn "  No origin/${ref} remote branch found (local-only work!)"
                echo "  Fix: git push -u origin ${ref} (then open a PR)"
            fi
        fi

        echo ""
        FOUND_UNMERGED=1
    fi
done <<< "$WIP_REFS"

if [[ $FOUND_UNMERGED -eq 1 ]]; then
    echo ""
    warn "Action required:"
    echo "  1. Review stranded branches above"
    echo "  2. Push local-only branches, open PRs (draft is fine)"
    echo "  3. Merge or cherry-pick needed commits to trunk"
    echo "  4. Delete merged branches (and cleanup worktrees)"
    echo ""
else
    info "No stranded commits detected (all checkpoint/WIP commits are merged to trunk)"
fi
