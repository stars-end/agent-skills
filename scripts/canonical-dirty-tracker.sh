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
atomic_write() {
    local content="$1"
    local tmp_file
    tmp_file=$(mktemp "$STATE_FILE.XXXXXX")
    echo "$content" > "$tmp_file"
    mv "$tmp_file" "$STATE_FILE"
}

# Simple JSON escape
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    echo "$str"
}

# Check if repo is dirty
is_dirty() {
    local repo_path="$1"
    cd "$repo_path"
    [[ -n $(git status --porcelain 2>/dev/null) ]]
}

# Get diffstat (escaped for JSON)
get_diffstat() {
    local repo_path="$1"
    cd "$repo_path"
    local stat
    stat=$(git diff --stat 2>/dev/null | tail -1 || echo "0 files")
    json_escape "$stat"
}

# Check all repos and update state
check_repos() {
    local now
    now=$(date +%s)
    local state
    state=$(cat "$STATE_FILE")
    
    for repo in "${CANONICAL_REPOS[@]}"; do
        local repo_path="$HOME/$repo"
        
        if [[ ! -d "$repo_path/.git" ]]; then
            continue
        fi
        
        if is_dirty "$repo_path"; then
            local diffstat
            diffstat=$(get_diffstat "$repo_path")
            
            # Check if already tracked
            local existing_start existing_end
            existing_start=$(echo "$state" | grep -o "\"$repo\":{" || true)
            
            if [[ -n "$existing_start" ]]; then
                # Update existing entry - extract and update
                local first_seen first_ts age_hours
                # Extract first_seen using simple pattern matching
                first_seen=$(echo "$state" | grep -o "\"$repo\":{[^}]*}" | grep -o '"first_seen":"[^"]*"' | cut -d'"' -f4 || true)
                
                if [[ -n "$first_seen" ]]; then
                    # Parse ISO timestamp to epoch (macOS compatible)
                    first_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$first_seen" +%s 2>/dev/null || echo "$now")
                    age_hours=$(( (now - first_ts) / 3600 ))
                else
                    first_seen=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                    age_hours=0
                fi
                
                # Update the entry by replacing it
                local new_entry="\"$repo\":{\"first_seen\":\"$first_seen\",\"last_seen\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"age_hours\":$age_hours,\"diffstat\":\"$diffstat\"}"
                
                # Replace old entry with new
                state=$(echo "$state" | sed "s/\"$repo\":{[^}]*}/$new_entry/")
            else
                # New entry
                local new_entry="\"$repo\":{\"first_seen\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"last_seen\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"age_hours\":0,\"diffstat\":\"$diffstat\"}"
                
                if [[ "$state" == "{}" ]]; then
                    state="{$new_entry}"
                else
                    # Remove trailing brace, add comma + new entry + closing brace
                    state="${state%\}},${new_entry}}"
                fi
            fi
        else
            # Repo is clean - remove from tracking
            state=$(echo "$state" | sed "s/\"$repo\":{[^,}]*}[,$]*//" | sed 's/,,/,/g' | sed 's/{,/{/g')
        fi
    done
    
    atomic_write "$state"
}

# Report current state
report() {
    cat "$STATE_FILE"
}

# Check for stale repos (>=48h)
check_stale() {
    local state
    state=$(cat "$STATE_FILE")
    local stale_repos=()
    
    # Extract each repo and check age
    for repo in "${CANONICAL_REPOS[@]}"; do
        local entry age
        entry=$(echo "$state" | grep -o "\"$repo\":{[^}]*}" || true)
        
        if [[ -n "$entry" ]]; then
            age=$(echo "$entry" | grep -o '"age_hours":[0-9]*' | cut -d: -f2 || echo "0")
            if [[ -n "$age" && "$age" -ge "$STALE_THRESHOLD_HOURS" ]]; then
                stale_repos+=("$repo:$age")
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
