#!/usr/bin/env bash
#
# scripts/canonical-sync-v8.sh (V8.6)
#
# Purpose: Evacuate canonical repo changes to rescue branches and reset to master.
# Cron schedule: daily at 3:05 AM
# Bead: bd-obyk
#
# Invariants:
# 1. NEVER reset canonical unless push succeeded.
# 2. Use diff-based file copy, NOT rsync.
# 3. Use porcelain git output.
# 4. Idempotent.
# 5. Controller-only write behavior for GitHub/pushing actions.
#
set -euo pipefail

# Configuration
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.dx-state"
RECOVERY_LOG="$STATE_DIR/recovery-commands.log"
CANONICAL_SYNC_SKIP_REASON_PREFIX="skip"
DX_CONTROLLER="${DX_CONTROLLER:-0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--verbose]"
            exit 1
            ;;
    esac
done

log() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "$1"
    fi
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

mkdir -p "$STATE_DIR"
touch "$RECOVERY_LOG"

push_without_hooks() {
    # Canonical rescue must not depend on local hook/toolchain state.
    # Disable hooks for this push path only.
    git -c core.hooksPath=/dev/null push "$@"
}

iso_timestamp() {
    date -u +"%Y%m%dT%H%M%SZ"
}

short_hostname() {
    hostname -s 2>/dev/null || hostname | cut -d'.' -f1
}

update_heartbeat() {
    local heartbeat="$HOME/.dx-state/HEARTBEAT.md"
    [[ -f "$heartbeat" ]] || return 0

    local section_start="### Canonical Repos"
    local status="$1"  # OK, WARNING, ERROR
    local details="$2"

    local tmpfile
    tmpfile=$(mktemp)
    awk -v start="$section_start" -v status="$status" -v details="$details" -v now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
        BEGIN { in_section=0; printed=0; gsub(/\\n/, "\n", details) }
        $0 == start {
            in_section=1; printed=1
            print start
            print "<!-- Updated by canonical-sync-v8.sh -->"
            print "Status: " status
            print "Last run: " now
            if (details != "") print details
            print ""
            next
        }
        /^### / && in_section { in_section=0 }
        !in_section { print }
    ' "$heartbeat" > "$tmpfile" && mv "$tmpfile" "$heartbeat"
}

log_recovery() {
    local repo="$1"
    local status="$2"
    local reason="$3"
    local branch="$4"
    local detail="$5"

    local ts host
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    host="$(short_hostname)"

    local line="${ts} | script=canonical-sync-v8 | repo=${repo} | host=${host} | status=${status} | reason=${reason}"
    if [[ -n "$branch" ]]; then
        line+=" | branch=${branch}"
    fi
    if [[ -n "$detail" ]]; then
        line+=" | ${detail}"
    fi

    echo "$line" >> "$RECOVERY_LOG"
}

controller_can_write() {
    if [[ "$DX_CONTROLLER" == "1" ]]; then
        return 0
    fi
    return 1
}

# bd-kuhj.5: Protection functions for automated cleanup
is_tmux_attached_to_path() {
    local target_path="$1"
    command -v tmux >/dev/null 2>&1 || return 1

    while IFS=$'\t' read -r attached pane_path; do
        [[ "$attached" == "1" ]] || continue
        [[ "$pane_path" == "$target_path"* ]] && return 0
    done < <(tmux list-panes -a -F '#{session_attached}	#{pane_current_path}' 2>/dev/null || true)

    return 1
}

is_working_hours() {
    local start_hour="${WORKTREE_CLEANUP_PROTECT_START:-8}"
    local end_hour="${WORKTREE_CLEANUP_PROTECT_END:-18}"
    local current_hour
    current_hour=$(date +%H)
    
    [[ "$current_hour" -ge "$start_hour" && "$current_hour" -lt "$end_hour" ]]
}

has_active_worktrees() {
    local repo_path="$1"
    local worktree_count
    worktree_count=$(git -C "$repo_path" worktree list 2>/dev/null | wc -l)
    [[ "$worktree_count" -gt 1 ]]
}

check_destructive_protection() {
    local repo_path="$1"
    local repo="$2"
    
    # Skip protection if explicitly disabled
    if [[ "${CANONICAL_SYNC_SKIP_PROTECTION:-0}" == "1" ]]; then
        return 0
    fi
    
    # Working hours protection
    if is_working_hours; then
        if [[ "${WORKTREE_CLEANUP_ALLOW_WORKING_HOURS:-0}" != "1" ]]; then
            warn "$repo: Working hours protection active, skipping destructive reset"
            log_recovery "$repo" "skip" "working_hours_protection" "" "policy=destructive-reset-blocked"
            return 1
        fi
    fi
    
    # Check for tmux-attached worktrees
    local worktree_paths
    worktree_paths="$(git -C "$repo_path" worktree list --porcelain 2>/dev/null | grep "^worktree" | cut -d' ' -f2 || true)"
    while IFS= read -r wt_path; do
        [[ -n "$wt_path" ]] || continue
        if is_tmux_attached_to_path "$wt_path"; then
            warn "$repo: Active tmux session at worktree: $wt_path"
            log_recovery "$repo" "skip" "tmux_attached_worktree" "" "worktree=$wt_path"
            return 1
        fi
    done <<< "$worktree_paths"
    
    return 0
}

process_repo() {
    local repo="$1"
    local repo_path="$HOME/$repo"
    local host
    host=$(short_hostname)

    log "\n📁 Processing canonical: $repo"

    if [[ ! -d "$repo_path/.git" ]]; then
        warn "$repo_path is not a git repository, skipping"
        log_recovery "$repo" "skip" "missing_repo" "" "path=${repo_path}"
        return 0
    fi

    local has_write_authority=false
    if controller_can_write; then
        has_write_authority=true
    fi

    # Skip if locked
    if [[ -f "$repo_path/.git/index.lock" ]]; then
        warn "$repo: .git/index.lock exists, skipping"
        log_recovery "$repo" "skip" "locked_index" "" "path=${repo_path}"
        return 0
    fi

    if [[ -x "$SCRIPT_DIR/dx-session-lock.sh" ]]; then
        if "$SCRIPT_DIR/dx-session-lock.sh" is-fresh "$repo_path"; then
            warn "$repo: Active session lock found, skipping"
            log_recovery "$repo" "skip" "branch_locked_by_worktree" "" "path=${repo_path}"
            return 0
        fi
    fi

    cd "$repo_path"

    # Fetch origin master
    if [[ "$DRY_RUN" == false ]]; then
        git fetch origin master --quiet || { warn "$repo: Failed to fetch origin master"; log_recovery "$repo" "skip" "fetch_failed" "" "path=origin/master"; }
    else
        log "[DRY-RUN] Would fetch origin master"
    fi

    # Detect state
    local current_branch
    current_branch=$(git branch --show-current)
    local is_dirty=false
    if [[ -n $(git status --porcelain) ]]; then
        is_dirty=true
    fi

    local is_off_trunk=false
    if [[ "$current_branch" != "master" ]]; then
        is_off_trunk=true
    fi

    if [[ "$is_dirty" == false && "$is_off_trunk" == false ]]; then
        log "$repo: Already clean and on master"
        log_recovery "$repo" "skip" "clean" "" "branch=${current_branch}"
        return 0
    fi

    echo "🚨 $repo needs rescue (branch: $current_branch, dirty: $is_dirty)"

    if [[ "$is_off_trunk" == true ]]; then
        local ahead
        ahead=$(git rev-list --count origin/master..HEAD 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            log "$repo: Branch '$current_branch' is ahead of origin/master by $ahead commits. Pushing branch..."
            if [[ "$DRY_RUN" == true ]]; then
                log "[DRY-RUN] Would push branch '$current_branch'"
                log_recovery "$repo" "skip" "off_trunk_ahead" "$current_branch" "ahead=$ahead controller=${DX_CONTROLLER}"
            elif [[ "$has_write_authority" == "true" ]]; then
                if git push --set-upstream origin "$current_branch" >/dev/null 2>&1; then
                    log_recovery "$repo" "evacuated" "off_trunk_push" "$current_branch" "ahead=${ahead}"
                else
                    error "$repo: Push failed for branch '$current_branch'"
                    log_recovery "$repo" "failed" "push_failed" "$current_branch" "ahead=${ahead}"
                    return 1
                fi
            else
                warn "$repo: Not controller, skip canonical writes for off-trunk branch"
                log_recovery "$repo" "skip" "off_trunk_controller_only" "$current_branch" "ahead=${ahead}"
            fi
        elif [[ "$DRY_RUN" == true ]]; then
            log "[DRY-RUN] Would skip clean off-trunk reset check"
        fi

        # Off-trunk but clean/behind/no push candidate
        if [[ "$is_dirty" == false ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log "[DRY-RUN] Would evaluate reset-to-master for off-trunk clean state"
                log_recovery "$repo" "skip" "off_trunk_clean" "$current_branch" "ahead=${ahead}"
                return 0
            fi

            if [[ "$has_write_authority" == true ]]; then
                log "$repo: Off-trunk but clean, resetting to master..."
                git checkout master -q
                git reset --hard origin/master
                git clean -fdq
                success "$repo: Reset to clean master"
                log_recovery "$repo" "evacuated" "off_trunk_clean_reset" "$current_branch" "ahead=${ahead}"
                return 0
            fi

            warn "$repo: Not controller, skipped off_trunk clean reset"
            log_recovery "$repo" "skip" "off_trunk_clean_noop" "$current_branch" "ahead=${ahead}"
            return 0
        fi
    fi

    # Dirty branch: evacuate to rescue worktree + reset canonical after successful push
    local timestamp
    timestamp=$(iso_timestamp)
    local rescue_branch="rescue-${host}-${repo}-${timestamp}"
    local rescue_dir="/tmp/agents/rescue-${repo}-$$"

    if [[ "$is_dirty" == true ]]; then
        log "Evacuating dirty changes to $rescue_branch..."

        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY-RUN] Would evacuate dirty changes to $rescue_branch and reset canonical"
            log_recovery "$repo" "skip" "dirty_timeout_noop" "$current_branch" "branch=${current_branch}"
            return 0
        fi

        if [[ "$has_write_authority" == false ]]; then
            warn "$repo: Not controller, skipped dirty rescue write actions"
            log_recovery "$repo" "skip" "dirty_timeout_controller_only" "$current_branch" "branch=${current_branch}"
            return 0
        fi

        # 1. Create rescue worktree
        if ! git worktree add -b "$rescue_branch" "$rescue_dir" origin/master >/dev/null 2>&1; then
            error "$repo: Failed to create rescue worktree at $rescue_dir"
            log_recovery "$repo" "failed" "worktree_create_failed" "$rescue_branch" "branch=${current_branch}"
            return 1
        fi

        # 2. Copy changed files via porcelain status (staged + unstaged + untracked)
        git status --porcelain | while IFS= read -r status_line; do
            # status_line format: "XY filename" or "XY filename -> renamed"
            local xy="${status_line:0:2}"
            local file="${status_line:3}"

            # Handle renames: "R  old -> new"
            if [[ "$file" == *" -> "* ]]; then
                file="${file##* -> }"
            fi

            # Skip deletions — nothing to copy
            local x="${xy:0:1}"
            local y="${xy:1:1}"
            if [[ "$x" == "D" || "$y" == "D" ]]; then
                continue
            fi

            # Skip if file doesn't exist (race condition safety)
            if [[ ! -e "$repo_path/$file" ]]; then
                continue
            fi

            # Copy preserving directory structure
            mkdir -p "$rescue_dir/$(dirname "$file")"
            cp -a "$repo_path/$file" "$rescue_dir/$file"
        done

        # 3. Commit in rescue worktree
        cd "$rescue_dir"
        git add -A
        if git commit -m "chore(rescue): evacuate canonical ($host $repo)

Original-Branch: $current_branch
Feature-Key: RESCUE-${host}-${repo}
Agent: canonical-sync-v8" --quiet; then
            log "Committed rescue changes"
        else
            log "Nothing to commit in rescue worktree"
        fi

        # 4. Push rescue branch
        if push_without_hooks -u origin "$rescue_branch" --quiet; then
            success "Pushed rescue branch $rescue_branch"

            # Log recovery command for digest/alerting
            log_recovery "$repo" "evacuated" "dirty_timeout" "$rescue_branch" "source=$current_branch"

            # bd-kuhj.5: Check protection before destructive reset
            if ! check_destructive_protection "$repo_path" "$repo"; then
                warn "$repo: Protection triggered, rescue branch pushed but canonical NOT reset"
                log_recovery "$repo" "skip" "protection_after_rescue" "$rescue_branch" "source=$current_branch rescue_pushed=true"
                git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
                rm -rf "$rescue_dir" 2>/dev/null || true
                return 0
            fi

            # NOW safe to reset canonical
            cd "$repo_path"
            git checkout master -q
            git reset --hard origin/master
            git clean -fdq
            git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
            rm -rf "$rescue_dir" 2>/dev/null || true
            success "$repo: Reset to clean master"
            log_recovery "$repo" "evacuated" "dirty_reset" "$rescue_branch" "source=$current_branch"
        else
            error "$repo: Push failed for $rescue_branch — canonical NOT reset"
            git worktree remove "$rescue_dir" --force >/dev/null 2>&1 || true
            rm -rf "$rescue_dir" 2>/dev/null || true
            log_recovery "$repo" "failed" "rescue_push_failed" "$rescue_branch" "source=$current_branch"
            return 1
        fi
    fi
}

main() {
    echo "🧹 DX Canonical Sync V8"
    echo "======================="

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN MODE]"
    fi

    local controller_state="off"
    if [[ "$DX_CONTROLLER" == "1" ]]; then
        controller_state="on"
    fi
    echo "Controller write mode: $controller_state"

    local fail_count=0
    for repo in "${CANONICAL_REPOS[@]}"; do
        process_repo "$repo" || ((fail_count++))
    done

    echo ""
    echo "======================="
    echo "Canonical sync complete"

    local status="OK"
    if [[ $fail_count -gt 0 ]]; then status="WARNING"; fi
    update_heartbeat "$status" "Failed: $fail_count"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] No actual changes made"
    fi
}

main "$@"
