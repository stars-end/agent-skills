#!/usr/bin/env bash
#
# dx-audit.sh - V8 Invariant Audit
#
# Checks V8 DX invariants across all repos and outputs structured data
# for LLM analysis (openclawd, gemini, etc.)
#
# Usage: dx-audit.sh [--json] [--slack] [--output FILE]
#
# Invariants checked:
#   1. Canonical repos read-only (rescue branch evidence)
#   2. Feature-Key trailer compliance
#   3. No auto-merge enabled on PRs
#   4. Agent: trailer present on commits
#   5. PR-to-beads linkage
#
# Schedule: Weekly via system cron (OpenClaw native cron is broken)
# Cron: 0 7 * * 0 /bin/bash -c 'source ~/.bashrc; MSG=$(~/agent-skills/scripts/dx-audit.sh --slack); /bin/bash ~/agent-skills/scripts/dx-audit-cron.sh'
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=("stars-end/agent-skills" "stars-end/prime-radiant-ai" "stars-end/affordabot" "stars-end/llm-common")
LOOKBACK_DAYS=7
OUTPUT_FORMAT="markdown"
OUTPUT_FILE=""
RECOVERY_LOG="$HOME/.dx-state/recovery-commands.log"

FOUNDER_STATUS="unknown"
FOUNDER_LAST_SUCCESS_AT=""
FOUNDER_LAST_SUCCESS_AGE_MIN=""
FOUNDER_LAST_FAILURE_AT=""
FOUNDER_LAST_FAILURE_REASON=""
FOUNDER_LAST_FAILURE_AGE_MIN=""
FOUNDER_LAST_TRANSPORT_FAILURE_AT=""
FOUNDER_LAST_TRANSPORT_FAILURE_AGE_MIN=""
FOUNDER_LAST_SUCCESS_SOURCE=""
FOUNDER_LAST_FAILURE_SOURCE=""
FOUNDER_LAST_TRANSPORT_FAILURE_SOURCE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --slack) OUTPUT_FORMAT="slack"; shift ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --help) echo "Usage: dx-audit.sh [--json] [--slack] [--output FILE]"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CUTOFF_DATE=$(date -u -v-${LOOKBACK_DAYS}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "${LOOKBACK_DAYS} days ago" +"%Y-%m-%dT%H:%M:%SZ")
CUTOFF_EPOCH=$(date -u -v-${LOOKBACK_DAYS}d +%s 2>/dev/null || date -u -d "${LOOKBACK_DAYS} days ago" +%s)

iso_to_epoch() {
  local iso="$1"
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || date -u -d "$iso" +%s 2>/dev/null || echo ""
}

json_or_null() {
  local value="$1"
  if [[ -n "$value" && "$value" != "null" ]]; then
    printf '"%s"' "$value"
  else
    printf 'null'
  fi
}

get_founder_health_from_recovery_log() {
  local now epoch_now founder_now
  now="$(date -u +%s)"

  if [[ ! -f "$RECOVERY_LOG" ]]; then
    return 0
  fi

  python3 - "$RECOVERY_LOG" "$now" <<'PY'
import json
import re
import sys

path = sys.argv[1]
now = int(sys.argv[2])

def to_epoch(iso):
    try:
        import datetime
        return int(__import__('datetime').datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=__import__('datetime').timezone.utc).timestamp())
    except Exception:
        return None

success_epoch = None
success_source = None
failure_epoch = None
failure_reason = ""
failure_source = None
transport_failure_epoch = None
transport_failure_source = None

line_re = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) \| (.*)$")

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    for raw in f:
        raw = raw.strip()
        if not raw:
            continue
        m = line_re.match(raw)
        if not m:
            continue
        ts = m.group(1)
        payload = m.group(2)
        parts = [p.strip() for p in payload.split(' | ') if p.strip()]
        kv = {}
        for part in parts:
            if '=' in part:
                k, v = part.split('=', 1)
                kv[k] = v
        if kv.get('script') != 'founder-briefing':
            continue

        status = kv.get('status', 'unknown')
        reason = kv.get('reason', '')
        epoch = to_epoch(ts)
        if not epoch:
            continue

        if status == 'success':
            if success_epoch is None or epoch > success_epoch:
                success_epoch = epoch
                success_source = kv.get('source', None)
        else:
            if failure_epoch is None or epoch > failure_epoch:
                failure_epoch = epoch
                failure_reason = reason
                failure_source = kv.get('source', None)

        if status == 'failure' and reason.startswith('transport'):
            if transport_failure_epoch is None or epoch > transport_failure_epoch:
                transport_failure_epoch = epoch
                transport_failure_source = kv.get('source', None)

def age_mins(e):
    if e is None:
        return None
    return max(0, (now - e) // 60)

out = {
    "status": "unknown",
    "last_success_at": None,
    "last_success_age_min": None,
    "last_success_source": None,
    "last_failure_at": None,
    "last_failure_reason": None,
    "last_failure_source": None,
    "last_failure_age_min": None,
    "last_transport_failure_at": None,
    "last_transport_failure_age_min": None,
    "last_transport_failure_source": None,
}

if success_epoch is not None:
    out["last_success_at"] = success_epoch
    out["last_success_age_min"] = age_mins(success_epoch)
    out["last_success_source"] = success_source

if failure_epoch is not None:
    out["last_failure_at"] = failure_epoch
    out["last_failure_reason"] = failure_reason
    out["last_failure_age_min"] = age_mins(failure_epoch)
    out["last_failure_source"] = failure_source

if transport_failure_epoch is not None:
    out["last_transport_failure_at"] = transport_failure_epoch
    out["last_transport_failure_age_min"] = age_mins(transport_failure_epoch)
    out["last_transport_failure_source"] = transport_failure_source

if success_epoch is None and failure_epoch is None:
    out["status"] = "unknown"
elif failure_epoch is not None and (success_epoch is None or failure_epoch >= success_epoch):
    out["status"] = "failed"
else:
    out["status"] = "ok"

print(json.dumps(out))
PY
}

founder_health_json="$(get_founder_health_from_recovery_log || true)"
if [[ -n "$founder_health_json" ]]; then
  FOUNDER_STATUS="$(jq -r '.status' <<<"$founder_health_json")"
  raw_epoch="$(jq -r '.last_success_at // empty' <<<"$founder_health_json")"
  if [[ -n "$raw_epoch" && "$raw_epoch" != "null" ]]; then
    FOUNDER_LAST_SUCCESS_AT="$(date -u -d "@$raw_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$raw_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    FOUNDER_LAST_SUCCESS_AGE_MIN="$(jq -r '.last_success_age_min // empty' <<<"$founder_health_json")"
    FOUNDER_LAST_SUCCESS_SOURCE="$(jq -r '.last_success_source // empty' <<<"$founder_health_json")"
  fi
  raw_epoch="$(jq -r '.last_failure_at // empty' <<<"$founder_health_json")"
  if [[ -n "$raw_epoch" && "$raw_epoch" != "null" ]]; then
    FOUNDER_LAST_FAILURE_AT="$(date -u -d "@$raw_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$raw_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    FOUNDER_LAST_FAILURE_AGE_MIN="$(jq -r '.last_failure_age_min // empty' <<<"$founder_health_json")"
    FOUNDER_LAST_FAILURE_REASON="$(jq -r '.last_failure_reason // empty' <<<"$founder_health_json")"
    FOUNDER_LAST_FAILURE_SOURCE="$(jq -r '.last_failure_source // empty' <<<"$founder_health_json")"
  fi
  raw_epoch="$(jq -r '.last_transport_failure_at // empty' <<<"$founder_health_json")"
  if [[ -n "$raw_epoch" && "$raw_epoch" != "null" ]]; then
    FOUNDER_LAST_TRANSPORT_FAILURE_AT="$(date -u -d "@$raw_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$raw_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    FOUNDER_LAST_TRANSPORT_FAILURE_AGE_MIN="$(jq -r '.last_transport_failure_age_min // empty' <<<"$founder_health_json")"
    FOUNDER_LAST_TRANSPORT_FAILURE_SOURCE="$(jq -r '.last_transport_failure_source // empty' <<<"$founder_health_json")"
  fi
fi

rescue_branch_to_iso() {
  local branch="$1"
  local ts
  ts=$(echo "$branch" | sed -nE 's/.*-([0-9]{8}T[0-9]{6}Z)$/\1/p')
  [[ -z "$ts" ]] && return 1
  echo "${ts:0:4}-${ts:4:2}-${ts:6:2}T${ts:9:2}:${ts:11:2}:${ts:13:2}Z"
}

# Initialize counters
declare -A rescue_counts
declare -A missing_feature_key
declare -A missing_agent_trailer
declare -A auto_merge_enabled
declare -A stale_prs
declare -A draft_prs
declare -A skill_drift_count
total_rescue=0
total_missing_fk=0
total_missing_agent=0
total_auto_merge=0
total_stale=0
total_draft=0
total_skill_drift=0
rescue_events=""

echo "# V8 Invariant Audit" >&2
echo "# Generated: $TS" >&2
echo "# Lookback: ${LOOKBACK_DAYS} days" >&2
echo "" >&2

# Check each repo
for repo in "${REPOS[@]}"; do
  repo_name=$(basename "$repo")
  echo "Auditing $repo..." >&2

  # 1. Rescue branch events within lookback window (canonical violation evidence)
  rescue_branches=$(gh api "repos/$repo/branches" --paginate --jq '.[].name | select(startswith("rescue-"))' 2>/dev/null || echo "")
  rescue_count=0

  if [[ -n "$rescue_branches" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      branch_ts="$(rescue_branch_to_iso "$branch" || true)"
      if [[ -z "$branch_ts" ]]; then
        continue
      fi
      branch_epoch="$(iso_to_epoch "$branch_ts")"
      if [[ -z "$branch_epoch" || "$branch_epoch" -lt "$CUTOFF_EPOCH" ]]; then
        continue
      fi
      rescue_count=$((rescue_count + 1))
      rescue_events="${rescue_events}| ${branch_ts} | ${branch} | ${repo_name} |\n"
    done <<< "$rescue_branches"
  fi
  rescue_counts[$repo_name]=$rescue_count
  total_rescue=$((total_rescue + rescue_count))

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

  # 7. Skill Drift (Local Check)
  repo_path="$HOME/$repo_name"
  drift_count=0
  if [[ -d "$repo_path/.claude/skills" ]]; then
    for skill_file in "$repo_path"/.claude/skills/*/SKILL.md; do
      [[ -e "$skill_file" ]] || continue
      missing=$(perl -lne 'print $1 while /`([^`]+\.(?:py|ts|tsx|sql|sh|yml|yaml))` /g' "$skill_file" | while read -r f; do
        [[ -f "$repo_path/$f" ]] || echo "$f"
      done | wc -l)
      drift_count=$((drift_count + missing))
    done
  fi
  skill_drift_count[$repo_name]=$drift_count
  total_skill_drift=$((total_skill_drift + drift_count))
done

# Generate output
founder_success_at_json="$(json_or_null "$FOUNDER_LAST_SUCCESS_AT")"
founder_success_age_json="$(json_or_null "$FOUNDER_LAST_SUCCESS_AGE_MIN")"
founder_success_source_json="$(json_or_null "$FOUNDER_LAST_SUCCESS_SOURCE")"
founder_failure_at_json="$(json_or_null "$FOUNDER_LAST_FAILURE_AT")"
founder_failure_age_json="$(json_or_null "$FOUNDER_LAST_FAILURE_AGE_MIN")"
founder_failure_reason_json="$(json_or_null "$FOUNDER_LAST_FAILURE_REASON")"
founder_failure_source_json="$(json_or_null "$FOUNDER_LAST_FAILURE_SOURCE")"
founder_transport_at_json="$(json_or_null "$FOUNDER_LAST_TRANSPORT_FAILURE_AT")"
founder_transport_age_json="$(json_or_null "$FOUNDER_LAST_TRANSPORT_FAILURE_AGE_MIN")"
founder_transport_source_json="$(json_or_null "$FOUNDER_LAST_TRANSPORT_FAILURE_SOURCE")"

output=""

if [[ "$OUTPUT_FORMAT" == "markdown" ]]; then
  output="## V8 Invariant Audit
Generated: $TS
Lookback: ${LOOKBACK_DAYS} days

### Summary
| Metric | Count | Status |
|--------|-------|--------|
| Rescue branch events (${LOOKBACK_DAYS}d) | $total_rescue | $([ $total_rescue -eq 0 ] && echo '✅ OK' || echo '⚠️ VIOLATION') |
| Founder Pipeline | $FOUNDER_STATUS | $([ "$FOUNDER_STATUS" = "ok" ] && echo '✅ OK' || ([ "$FOUNDER_STATUS" = "failed" ] && echo '🚨 ACTION NEEDED' || echo '⚠️ UNKNOWN')) |
| Founder failure reason | ${FOUNDER_LAST_FAILURE_REASON:-none} | $([ "$FOUNDER_STATUS" = "failed" ] && echo '🚨' || echo 'ℹ️') |
| Founder pipeline source (last success/failure) | ${FOUNDER_LAST_SUCCESS_SOURCE:-unknown} / ${FOUNDER_LAST_FAILURE_SOURCE:-none} | ℹ️ INFO |
| Founder last success (mins ago) | ${FOUNDER_LAST_SUCCESS_AGE_MIN:-unknown} | $(if [[ -n "${FOUNDER_LAST_SUCCESS_AGE_MIN}" ]]; then echo 'ℹ️ INFO'; else echo '⚠️ UNKNOWN'; fi) |
| Founder transport failure age (mins ago) | ${FOUNDER_LAST_TRANSPORT_FAILURE_AGE_MIN:-none} | $(if [[ -n "${FOUNDER_LAST_TRANSPORT_FAILURE_AGE_MIN}" ]]; then echo '⚠️ WATCH'; else echo '✅ OK'; fi) |
| Commits missing Feature-Key | $total_missing_fk | $([ $total_missing_fk -lt 5 ] && echo '✅ OK' || echo '⚠️ CHECK') |
| Commits missing Agent: trailer | $total_missing_agent | $([ $total_missing_agent -lt 5 ] && echo '✅ OK' || echo '⚠️ CHECK') |
| PRs with auto-merge enabled | $total_auto_merge | $([ $total_auto_merge -eq 0 ] && echo '✅ OK' || echo '❌ VIOLATION') |
| Skill Drift (missing files) | $total_skill_drift | $([ $total_skill_drift -eq 0 ] && echo '✅ OK' || echo '⚠️ DRIFT') |
| Stale PRs (>${LOOKBACK_DAYS}d) | $total_stale | $([ $total_stale -lt 3 ] && echo '✅ OK' || echo '⚠️ ATTENTION') |
| Draft PRs | $total_draft | ℹ️ INFO |

### Per-Repo Breakdown
| Repo | Rescue | Missing FK | Missing Agent | Auto-Merge | Drift | Stale | Draft |
|------|--------|------------|---------------|------------|-------|-------|-------|
"

  for repo in "${REPOS[@]}"; do
    name=$(basename "$repo")
    output="${output}
| $name | ${rescue_counts[$name]:-0} | ${missing_feature_key[$name]:-0} | ${missing_agent_trailer[$name]:-0} | ${auto_merge_enabled[$name]:-0} | ${skill_drift_count[$name]:-0} | ${stale_prs[$name]:-0} | ${draft_prs[$name]:-0} |"
  done

  if [[ -n "$rescue_events" ]]; then
    output="${output}

### Rescue Branch Events (Canonical Violations, ${LOOKBACK_DAYS}d)
| Timestamp | Branch | Repo |
|-----------|--------|------|
$(echo -e "$rescue_events")"
  fi

  output="${output}

### Invariant Definitions
1. **Rescue branch events (${LOOKBACK_DAYS}d)**: New rescue branches created during lookback. High count = canonical workflow violations.
2. **Feature-Key**: Every commit should have \`Feature-Key: bd-XXXX\` trailer for traceability.
3. **Agent trailer**: Every agent commit should have \`Agent: <name>\` trailer for attribution.
4. **Auto-merge**: Should NEVER be enabled. Humans merge, not bots.
5. **Stale PRs**: PRs not updated in >${LOOKBACK_DAYS} days may indicate blocked work.
6. **Founder pipeline**: Founder briefing should run successfully and post, including successful transport.
7. **Founder transport health**: Any transport failures indicate immediate action needed.
8. **Controller-only writes**: Only controller hosts execute destructive canonical operations.
"

elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
  output=$(cat <<EOF
{
  "generated_at": "$TS",
  "lookback_days": $LOOKBACK_DAYS,
  "summary": {
    "rescue_branches_lookback": $total_rescue,
    "rescue_branches": $total_rescue,
    "missing_feature_key": $total_missing_fk,
    "missing_agent_trailer": $total_missing_agent,
    "auto_merge_enabled": $total_auto_merge,
    "stale_prs": $total_stale,
    "draft_prs": $total_draft,
    "founder_pipeline": {
      "status": "$FOUNDER_STATUS",
      "last_success_at": $founder_success_at_json,
      "last_success_age_min": $founder_success_age_json,
      "last_success_source": $founder_success_source_json,
      "last_failure_at": $founder_failure_at_json,
      "last_failure_reason": $founder_failure_reason_json,
      "last_failure_source": $founder_failure_source_json,
      "last_failure_age_min": $founder_failure_age_json,
      "last_transport_failure_at": $founder_transport_at_json,
      "last_transport_failure_age_min": $founder_transport_age_json,
      "last_transport_failure_source": $founder_transport_source_json
    }
  },
  "by_repo": {
$(for repo in "${REPOS[@]}"; do
  name=$(basename "$repo")
  echo "    \"$name\": {"
  echo "      \"rescue_branches_lookback\": ${rescue_counts[$name]:-0},"
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

elif [[ "$OUTPUT_FORMAT" == "slack" ]]; then
  # Determine overall status
  status_emoji="✅"
  status_text="All green"

  if [ "$total_rescue" -gt 0 ] || [ "$total_auto_merge" -gt 0 ]; then
    status_emoji="🚨"
    status_text="V8 violations detected"
  elif [ "$total_stale" -gt 2 ] || [ "$total_skill_drift" -gt 0 ]; then
    status_emoji="⚠️"
    status_text="PR or Skill Drift detected"
  fi

  # Build main message (≤300 chars)
  output="${status_emoji} *V8 Weekly Audit* (${LOOKBACK_DAYS}d):
• Rescue events (${LOOKBACK_DAYS}d): ${total_rescue} $([ $total_rescue -eq 0 ] && echo '✅' || echo '❌')
• Auto-merge PRs: ${total_auto_merge} $([ $total_auto_merge -eq 0 ] && echo '✅' || echo '❌')
• Skill Drift: ${total_skill_drift} $([ $total_skill_drift -eq 0 ] && echo '✅' || echo '⚠️')
• Stale PRs: ${total_stale} | Drafts: ${total_draft}
• Founder Pipeline: ${FOUNDER_STATUS} | source=${FOUNDER_LAST_SUCCESS_SOURCE:-unknown} | reason=${FOUNDER_LAST_FAILURE_REASON:-none}
• Founder Transport Failure (mins ago): ${FOUNDER_LAST_TRANSPORT_FAILURE_AGE_MIN:-none}"

  # Add violation details if any
  if [ "$total_rescue" -gt 0 ] && [[ -n "$rescue_events" ]]; then
    output="${output}
---THREAD---
*Rescue Branch Events (Canonical Violations):*"
    # Parse rescue_events and format
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      output="${output}
${line}"
    done <<< "$(echo -e "$rescue_events")"
  fi
fi

# Output
if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$output" > "$OUTPUT_FILE"
  echo "Audit written to: $OUTPUT_FILE" >&2
else
  echo "$output"
fi
