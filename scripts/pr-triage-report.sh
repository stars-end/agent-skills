#!/usr/bin/env bash
# pr-triage-report.sh - Weekly PR triage report for Slack
# Part of V8 DX automation
#
# Usage:
#   ./pr-triage-report.sh              # Output to stdout
#   ./pr-triage-report.sh --slack      # Post to Slack via openclaw
#
# Cron (Sunday 8am PT):
#   0 8 * * 0 ~/agent-skills/scripts/pr-triage-report.sh --slack

set -euo pipefail

REPOS=(agent-skills prime-radiant-ai affordabot llm-common)
SLACK_CHANNEL="${DX_TRIAGE_CHANNEL:-C0ADSSZV9M2}"  # #dx-alerts default
STALE_DAYS=7

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

generate_report() {
    local total_open=0
    local total_stale=0
    local total_mergeable=0
    local report=""

    report+="📋 *Weekly PR Triage Report*\n"
    report+="_$(date '+%Y-%m-%d %H:%M') PT_\n\n"

    for repo in "${REPOS[@]}"; do
        local prs
        prs=$(gh pr list --repo "stars-end/$repo" --state open \
            --json number,title,createdAt,mergeable,isDraft,author,headRefName \
            2>/dev/null || echo "[]")

        local count
        count=$(echo "$prs" | jq 'length')

        if [ "$count" -eq 0 ]; then
            continue
        fi

        total_open=$((total_open + count))
        report+="\n*$repo* ($count open)\n"

        # Process each PR
        while IFS= read -r pr; do
            local num title created mergeable draft branch age_days
            num=$(echo "$pr" | jq -r '.number')
            title=$(echo "$pr" | jq -r '.title[:45]')
            created=$(echo "$pr" | jq -r '.createdAt')
            mergeable=$(echo "$pr" | jq -r '.mergeable')
            draft=$(echo "$pr" | jq -r '.isDraft')
            branch=$(echo "$pr" | jq -r '.headRefName')

            # Calculate age in days
            created_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" +%s 2>/dev/null || date -d "$created" +%s)
            now_ts=$(date +%s)
            age_days=$(( (now_ts - created_ts) / 86400 ))

            # Determine recommendation
            local recommendation=""
            local emoji=""

            if [ "$draft" = "true" ]; then
                emoji="📝"
                recommendation="DRAFT"
            elif [[ "$branch" =~ ^bot/ ]] || [[ "$branch" =~ ^auto-checkpoint/ ]]; then
                emoji="🤖"
                recommendation="CLOSE (bot)"
                total_stale=$((total_stale + 1))
            elif [ "$age_days" -gt "$STALE_DAYS" ]; then
                emoji="⏰"
                recommendation="STALE (${age_days}d)"
                total_stale=$((total_stale + 1))
            elif [ "$mergeable" = "MERGEABLE" ]; then
                emoji="✅"
                recommendation="MERGE"
                total_mergeable=$((total_mergeable + 1))
            elif [ "$mergeable" = "CONFLICTING" ]; then
                emoji="⚠️"
                recommendation="CONFLICT"
            else
                emoji="👀"
                recommendation="REVIEW"
            fi

            report+="  $emoji #$num: $title ($recommendation)\n"

        done < <(echo "$prs" | jq -c '.[]')
    done

    # Summary
    report+="\n---\n"
    report+="*Summary:* $total_open open | $total_mergeable ready to merge | $total_stale stale/bot\n"

    if [ "$total_mergeable" -gt 0 ]; then
        report+="\n_Quick merge commands:_\n\`\`\`\n"
        for repo in "${REPOS[@]}"; do
            local mergeable_prs
            mergeable_prs=$(gh pr list --repo "stars-end/$repo" --state open \
                --json number,mergeable,isDraft,headRefName \
                --jq '.[] | select(.mergeable == "MERGEABLE" and .isDraft == false and (.headRefName | test("^(bot/|auto-checkpoint/)") | not)) | .number' \
                2>/dev/null || echo "")

            for num in $mergeable_prs; do
                report+="gh pr merge $num --repo stars-end/$repo --squash\n"
            done
        done
        report+="\`\`\`\n"
    fi

    echo -e "$report"
}

post_to_slack() {
    local report="$1"
    local openclaw_bin="$HOME/.local/bin/mise x node@22.21.1 -- openclaw"

    if command -v "$HOME/.local/bin/mise" &> /dev/null; then
        $openclaw_bin message send --channel slack --target "$SLACK_CHANNEL" --message "$report" 2>/dev/null && return 0
    fi

    # Fallback: just print
    echo "⚠️  Could not post to Slack (openclaw not available)"
    echo "$report"
    return 1
}

main() {
    local report
    report=$(generate_report)

    if [ "${1:-}" = "--slack" ]; then
        post_to_slack "$report"
    else
        echo -e "$report"
    fi
}

main "$@"
