#!/usr/bin/env bash
# canonical-dirty-tracker.sh - Track dirty canonical incidents
# Usage: canonical-dirty-tracker.sh [check|report|stale]

set -euo pipefail

STATE_DIR="$HOME/.dx-state"
STATE_FILE="$STATE_DIR/dirty-incidents.json"
CANONICAL_REPOS=("agent-skills" "prime-radiant-ai" "affordabot" "llm-common")
STALE_THRESHOLD_HOURS=48

mkdir -p "$STATE_DIR"

# Initialize state file if missing
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
fi

# Atomic write helper
write_state() {
    local tmp_file=$(mktemp)
    cat > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}

# Check if repo is dirty
is_dirty() {
    local repo_path="$1"
    cd "$repo_path"
    [[ -n $(git status --porcelain 2>/dev/null) ]]
}

# Get diffstat
get_diffstat() {
    local repo_path="$1"
    cd "$repo_path"
    git diff --stat 2>/dev/null | tail -1 || echo "0 files changed"
}

# Check all repos and update state
check_repos() {
    local now=$(date -u +%s)
    local state=$(cat "$STATE_FILE")

    for repo in "${CANONICAL_REPOS[@]}"; do
        local repo_path="$HOME/$repo"

        if [[ ! -d "$repo_path/.git" ]]; then
            continue
        fi

        if is_dirty "$repo_path"; then
            local diffstat=$(get_diffstat "$repo_path")
            local existing=$(echo "$state" | grep -o "\"$repo\":[^}]*}" 2>/dev/null || echo "")

            if [[ -n "$existing" ]]; then
                # Update last_seen and age
                local first_seen=$(echo "$existing" | grep -o '"first_seen":"[^"]*"' | cut -d'"' -f4)
                local first_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$first_seen" +%s 2>/dev/null || echo "$now")
                local age_hours=$(( (now - first_ts) / 3600 ))

                # Update JSON entry
                state=$(echo "$state" | sed "s/\"$repo\":[^}]*}/\"$repo\":{\"first_seen\":\"$first_seen\",\"last_seen\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"age_hours\":$age_hours,\"diffstat\":\"$diffstat\"}/")
            else
                # New incident
                local entry="\"$repo\":{\"first_seen\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"last_seen\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"age_hours\":0,\"diffstat\":\"$diffstat\"}"
                if [[ "$state" == "{}" ]]; then
                    state="{$entry}"
                else
                    state=$(echo "$state" | sed "s/}$/,$entry}/")
                fi
            fi
        else
            # Repo is clean - remove from tracking if exists
            state=$(echo "$state" | sed "s/\"$repo\":[^,}]*,//;s/\"$repo\":[^}]*}//")
        fi
    done

    echo "$state" | write_state
}

# Report current state
report() {
    cat "$STATE_FILE"
}

# Check for stale repos (>=48h)
check_stale() {
    local state=$(cat "$STATE_FILE")
    local now=$(date -u +%s)
    local stale_repos=()

    for repo in "${CANONICAL_REPOS[@]}"; do
        local entry=$(echo "$state" | grep -o "\"$repo\":[^}]*}" 2>/dev/null || echo "")
        if [[ -n "$entry" ]]; then
            local age=$(echo "$entry" | grep -o '"age_hours":[0-9]*' | cut -d: -f2)
            if [[ -n "$age" && "$age" -ge "$STALE_THRESHOLD_HOURS" ]]; then
                stale_repos+=("$repo")
            fi
        fi
    done

    if [[ ${#stale_repos[@]} -gt 0 ]]; then
        echo "STALE_REPOS=${stale_repos[*]}"
        return 1
    fi
    echo "STALE_REPOS=none"
    return 0
}

# Main
ACTION="${1:-check}"

case "$ACTION" in
    check)
        check_repos
        ;;
    report)
        report
        ;;
    stale)
        check_stale
        ;;
    *)
        echo "Usage: $0 [check|report|stale]"
        exit 1
        ;;
esac
