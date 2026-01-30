#!/usr/bin/env bash
# auto-checkpoint-notify.sh
# Show stranded work on auto-checkpoint branches at session start
# Source this from .zshrc or .bashrc

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Only show once per session
MARKER_FILE="${TMPDIR:-/tmp}/auto-checkpoint-notify-shown.$$"

check_auto_checkpoint_branches() {
    local repo_path="$1"
    local repo_name
    repo_name=$(basename "$repo_path")

    # Skip if not a git repo
    [ -d "$repo_path/.git" ] || return 0

    cd "$repo_path" || return 0

    # Find auto-checkpoint branches with commits not in trunk
    local trunk_branch
    if git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        trunk_branch="master"
    elif git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        trunk_branch="main"
    else
        return 0
    fi

    local found_branches=()
    local branch_info=()

    # Check both local and remote auto-checkpoint branches
    for branch in $(git branch -a 2>/dev/null | grep -E "auto-checkpoint/" | sed 's|[* ] ||' | sed 's|remotes/origin/||' | sort -u); do
        # Skip if already merged
        if git log "$trunk_branch".."$branch" --oneline 2>/dev/null | grep -q .; then
            # Count commits and get timestamp
            local commit_count
            commit_count=$(git log "$trunk_branch".."$branch" --oneline 2>/dev/null | wc -l | tr -d ' ')
            
            # Get last commit time (approximate)
            local last_commit_ts
            last_commit_ts=$(git log -1 --format=%ct "$branch" 2>/dev/null || echo "0")
            
            local hours_old="unknown"
            if [[ "$last_commit_ts" != "0" ]]; then
                local now
                now=$(date +%s)
                local age_seconds=$((now - last_commit_ts))
                local age_hours=$((age_seconds / 3600))
                
                if [[ $age_hours -lt 24 ]]; then
                    hours_old="${age_hours}h ago"
                elif [[ $age_hours -lt 168 ]]; then
                    hours_old="$((age_hours / 24))d ago"
                else
                    hours_old="$((age_hours / 168))w ago"
                fi
            fi
            
            found_branches+=("$branch")
            branch_info+=("$commit_count commits, $hours_old")
        fi
    done

    if [[ ${#found_branches[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "${YELLOW}⚠️  Uncommitted work on ${repo_name}:${NC}"
    for i in "${!found_branches[@]}"; do
        echo -e "    • ${found_branches[$i]} (${branch_info[$i]})"
    done
    echo ""
}

main() {
    # Check if already shown this session
    if [ -f "$MARKER_FILE" ]; then
        return 0
    fi

    # Create marker file
    touch "$MARKER_FILE"

    # Check canonical repos
    local repos=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
    local found_any=0

    for repo in "${repos[@]}"; do
        local repo_path="$HOME/$repo"
        if [ -d "$repo_path" ]; then
            if check_auto_checkpoint_branches "$repo_path"; then
                found_any=1
            fi
        fi
    done

    if [[ $found_any -eq 1 ]]; then
        echo -e "${BLUE}Actions:${NC}"
        echo "  [M]erge to master:  git checkout master && git merge auto-checkpoint/<host>"
        echo "  [C]reate feature:   git checkout master && git checkout -b feature/my-work && git merge auto-checkpoint/<host>"
        echo "  [I]gnore:          Work will stay on auto-checkpoint branch"
        echo ""
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
