#!/usr/bin/env bash
#
# dx-audit.sh - V8 Invariant Audit
#
# Checks V8 DX invariants across all repos and outputs structured data
# for LLM analysis (openclawd, gemini, etc.)
#
# Usage: dx-audit.sh [--json] [--output FILE]
#
# Invariants checked:
#   1. Canonical repos read-only (rescue branch evidence)
#   2. Feature-Key trailer compliance
#   3. No auto-merge enabled on PRs
#   4. Agent: trailer present on commits
#   5. PR-to-beads linkage
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=("stars-end/agent-skills" "stars-end/prime-radiant-ai" "stars-end/affordabot" "stars-end/llm-common")
LOOKBACK_DAYS=7
OUTPUT_FORMAT="markdown"
OUTPUT_FILE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CUTOFF_DATE=$(date -u -v-${LOOKBACK_DAYS}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "${LOOKBACK_DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ")

# Initialize counters
declare -A rescue_counts
declare -A missing_feature_key
declare -A missing_agent_trailer
declare -A auto_merge_enabled
declare -A stale_prs
declare -A draft_prs
total_rescue=0
total_missing_fk=0
total_missing_agent=0
total_auto_merge=0
total_stale=0
total_draft=0
rescue_events=""

echo "# V8 Invariant Audit" >&2
echo "# Generated: $TS" >&2
echo "# Lookback: ${LOOKBACK_DAYS} days" >&2
echo "" >&2

# Check each repo
for repo in "${REPOS[@]}"; do
  repo_name=$(basename "$repo")
  echo "Auditing $repo..." >&2

  # 1. Rescue branches (canonical violation evidence)
  rescue_branches=$(gh api "repos/$repo/branches" --paginate --jq '.[].name | select(startswith("rescue-"))' 2>/dev/null || echo "")
  if [[ -n "$rescue_branches" ]]; then
    rescue_count=$(echo "$rescue_branches" | wc -l | tr -d ' ')
  else
    rescue_count=0
  fi
  rescue_counts[$repo_name]=$rescue_count
  total_rescue=$((total_rescue + rescue_count))

  if [[ -n "$rescue_branches" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      # Get last commit date on rescue branch
      commit_date=$(gh api "repos/$repo/branches/$branch" --jq '.commit.commit.committer.date' 2>/dev/null || echo "unknown")
      rescue_events="${rescue_events}| ${commit_date} | ${branch} | ${repo_name} |\n"
    done <<< "$rescue_branches"
  fi

  # 2. Feature-Key trailer compliance (recent commits on master)
  # Check last 20 commits for Feature-Key trailer
  commits_without_fk=$(gh api "repos/$repo/commits?sha=master&per_page=20" \
    --jq '.[].commit.message' 2>/dev/null | \
    grep -v "Feature-Key:" | grep -v "^\[" | grep -v "^Merge" | wc -l || echo "0")
  commits_without_fk=$(echo "$commits_without_fk" | tr -d ' ')
  missing_feature_key[$repo_name]=$commits_without_fk
  total_missing_fk=$((total_missing_fk + commits_without_fk))

  # 3. Agent: trailer compliance
  commits_without_agent=$(gh api "repos/$repo/commits?sha=master&per_page=20" \
    --jq '.[].commit.message' 2>/dev/null | \
    grep -v "Agent:" | grep -v "^\[" | grep -v "^Merge" | grep -v "github-actions" | wc -l || echo "0")
  commits_without_agent=$(echo "$commits_without_agent" | tr -d ' ')
  missing_agent_trailer[$repo_name]=$commits_without_agent
  total_missing_agent=$((total_missing_agent + commits_without_agent))

  # 4. Auto-merge enabled PRs
  auto_merge_prs=$(gh pr list --repo "$repo" --json autoMergeRequest,number \
    --jq '[.[] | select(.autoMergeRequest != null)] | length' 2>/dev/null || echo "0")
  auto_merge_enabled[$repo_name]=$auto_merge_prs
  total_auto_merge=$((total_auto_merge + auto_merge_prs))

  # 5. Stale PRs (>7 days)
  stale=$(gh pr list --repo "$repo" --json updatedAt \
    --jq "[.[] | select(.updatedAt < \"$CUTOFF_DATE\")] | length" 2>/dev/null || echo "0")
  stale_prs[$repo_name]=$stale
  total_stale=$((total_stale + stale))

  # 6. Draft PRs
  drafts=$(gh pr list --repo "$repo" --json isDraft \
    --jq '[.[] | select(.isDraft == true)] | length' 2>/dev/null || echo "0")
  draft_prs[$repo_name]=$drafts
  total_draft=$((total_draft + drafts))
done

# Generate output
output=""

if [[ "$OUTPUT_FORMAT" == "markdown" ]]; then
  output="## V8 Invariant Audit
Generated: $TS
Lookback: ${LOOKBACK_DAYS} days

### Summary
| Metric | Count | Status |
|--------|-------|--------|
| Rescue branches (canonical violations) | $total_rescue | $([ $total_rescue -eq 0 ] && echo '✅ OK' || echo '⚠️ VIOLATION') |
| Commits missing Feature-Key | $total_missing_fk | $([ $total_missing_fk -lt 5 ] && echo '✅ OK' || echo '⚠️ CHECK') |
| Commits missing Agent: trailer | $total_missing_agent | $([ $total_missing_agent -lt 5 ] && echo '✅ OK' || echo '⚠️ CHECK') |
| PRs with auto-merge enabled | $total_auto_merge | $([ $total_auto_merge -eq 0 ] && echo '✅ OK' || echo '❌ VIOLATION') |
| Stale PRs (>${LOOKBACK_DAYS}d) | $total_stale | $([ $total_stale -lt 3 ] && echo '✅ OK' || echo '⚠️ ATTENTION') |
| Draft PRs | $total_draft | ℹ️ INFO |

### Per-Repo Breakdown
| Repo | Rescue | Missing FK | Missing Agent | Auto-Merge | Stale | Draft |
|------|--------|------------|---------------|------------|-------|-------|"

  for repo in "${REPOS[@]}"; do
    name=$(basename "$repo")
    output="${output}
| $name | ${rescue_counts[$name]:-0} | ${missing_feature_key[$name]:-0} | ${missing_agent_trailer[$name]:-0} | ${auto_merge_enabled[$name]:-0} | ${stale_prs[$name]:-0} | ${draft_prs[$name]:-0} |"
  done

  if [[ -n "$rescue_events" ]]; then
    output="${output}

### Rescue Branch Events (Canonical Violations)
| Timestamp | Branch | Repo |
|-----------|--------|------|
$(echo -e "$rescue_events")"
  fi

  output="${output}

### Invariant Definitions
1. **Rescue branches**: Created when canonical-sync-v8 evacuates dirty repos. High count = agents editing canonicals.
2. **Feature-Key**: Every commit should have \`Feature-Key: bd-XXXX\` trailer for traceability.
3. **Agent trailer**: Every agent commit should have \`Agent: <name>\` trailer for attribution.
4. **Auto-merge**: Should NEVER be enabled. Humans merge, not bots.
5. **Stale PRs**: PRs not updated in >${LOOKBACK_DAYS} days may indicate blocked work.
"

elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
  output=$(cat <<EOF
{
  "generated_at": "$TS",
  "lookback_days": $LOOKBACK_DAYS,
  "summary": {
    "rescue_branches": $total_rescue,
    "missing_feature_key": $total_missing_fk,
    "missing_agent_trailer": $total_missing_agent,
    "auto_merge_enabled": $total_auto_merge,
    "stale_prs": $total_stale,
    "draft_prs": $total_draft
  },
  "by_repo": {
$(for repo in "${REPOS[@]}"; do
  name=$(basename "$repo")
  echo "    \"$name\": {"
  echo "      \"rescue_branches\": ${rescue_counts[$name]:-0},"
  echo "      \"missing_feature_key\": ${missing_feature_key[$name]:-0},"
  echo "      \"missing_agent_trailer\": ${missing_agent_trailer[$name]:-0},"
  echo "      \"auto_merge_enabled\": ${auto_merge_enabled[$name]:-0},"
  echo "      \"stale_prs\": ${stale_prs[$name]:-0},"
  echo "      \"draft_prs\": ${draft_prs[$name]:-0}"
  echo "    },"
done | sed '$ s/,$//')
  },
  "violations": {
    "canonical_protection": $([ $total_rescue -gt 0 ] && echo 'true' || echo 'false'),
    "auto_merge": $([ $total_auto_merge -gt 0 ] && echo 'true' || echo 'false')
  }
}
EOF
)
fi

# Output
if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$output" > "$OUTPUT_FILE"
  echo "Audit written to: $OUTPUT_FILE" >&2
else
  echo "$output"
fi
