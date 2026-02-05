#!/usr/bin/env bash
#
# dx-pr-gate.sh
#
# Check status of GitHub PRs with autoMerge enabled.
# Part of V7.8 Heartbeat.
#
set -euo pipefail

REPOS=(
    "stars-end/agent-skills"
    "stars-end/prime-radiant-ai"
    "stars-end/affordabot"
    "stars-end/llm-common"
)

BLOCKED=0
QUEUED=0
BLOCKERS=()

# Safety: Check if gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "PR GATE NOT OK: gh auth missing"
    exit 0
fi

for repo in "${REPOS[@]}"; do
    # Query for open PRs with autoMerge enabled
    # We want mergeStateStatus in {BLOCKED, BEHIND, DIRTY}
    # And we'll also count those that are already clean/ready (queued)
    prs=$(gh pr list --repo "$repo" --limit 10 --json number,title,mergeStateStatus,autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)')
    
    if [[ -z "$prs" ]]; then
        continue
    fi
    
    # Process each PR
    while IFS= read -r pr; do
        status=$(echo "$pr" | python3 -c "import sys, json; print(json.load(sys.stdin).get('mergeStateStatus'))")
        number=$(echo "$pr" | python3 -c "import sys, json; print(json.load(sys.stdin).get('number'))")
        title=$(echo "$pr" | python3 -c "import sys, json; print(json.load(sys.stdin).get('title'))")
        
        case "$status" in
            BLOCKED|BEHIND|DIRTY)
                ((BLOCKED += 1))
                if [[ ${#BLOCKERS[@]} -lt 4 ]]; then
                    BLOCKERS+=("#$number ($repo): $status - $title")
                fi
                ;;
            *)
                ((QUEUED += 1))
                ;;
        esac
    done <<< "$prs"
done

if [[ "$BLOCKED" -eq 0 && "$QUEUED" -eq 0 ]]; then
    echo "PR GATE OK (0 blocked, 0 queued)"
else
    if [[ "$BLOCKED" -gt 0 ]]; then
        echo "PR GATE NOT OK (blocked=$BLOCKED queued=$QUEUED)"
        for blocker in "${BLOCKERS[@]}"; do
            echo "  - $blocker"
        done
        echo "  Next: gh pr view <number>"
    else
        echo "PR GATE OK (0 blocked, $QUEUED queued)"
    fi
fi
