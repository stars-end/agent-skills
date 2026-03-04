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

# Fleet Sync V2.1 contract checks (local repo health)
FLEET_SYNC_ROOT="${HOME}/agent-skills"
FLEET_SYNC_SPEC_PRIMARY="${FLEET_SYNC_ROOT}/docs/FLEET_SYNC_SPEC.md"
FLEET_SYNC_SPEC_LEGACY="${FLEET_SYNC_ROOT}/docs/FLEET_SYNC_SPEC_V2.md"
FLEET_SYNC_MANIFEST="${FLEET_SYNC_ROOT}/configs/fleet-sync.manifest.yaml"
MCP_TOOLS_MANIFEST="${FLEET_SYNC_ROOT}/configs/mcp-tools.yaml"
FLEET_HOSTS_CONFIG="${FLEET_SYNC_ROOT}/configs/fleet_hosts.yaml"
FLEET_SYNC_SCRIPT="${FLEET_SYNC_ROOT}/scripts/dx-mcp-tools-sync.sh"
FLEET_SYNC_SKILL_STUBS=(
  "${FLEET_SYNC_ROOT}/extended/context-plus/SKILL.md"
  "${FLEET_SYNC_ROOT}/extended/cass-memory/SKILL.md"
  "${FLEET_SYNC_ROOT}/extended/llm-tldr/SKILL.md"
)
FLEET_SYNC_FORBIDDEN_REQUIRED_REGEX='supergateway|mcp-proxy'
FLEET_SYNC_EPYC12_REQUIRED_MAX=4
FLEET_SYNC_RUNTIME_SERVICE_CAP="${DX_FLEET_SERVICE_CAP:-4}"
FLEET_SYNC_MAX_TOOL_STALE_HOURS="${DX_FLEET_MAX_TOOL_STALE_HOURS:-24}"
FLEET_SYNC_MAX_DOLT_STALE_MINUTES="${DX_FLEET_MAX_DOLT_STALE_MINUTES:-60}"

extract_epyc12_required_services() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 0
  awk '
    BEGIN {in_runtime=0; in_required=0; in_epyc12=0}
    /^runtime_services:/ {in_runtime=1; next}
    in_runtime && /^distribution:/ {in_runtime=0; in_required=0; in_epyc12=0}
    in_runtime && /^  required:/ {in_required=1; next}
    in_runtime && /^  optional:/ {in_required=0; in_epyc12=0; next}
    in_required && /^    epyc12:/ {in_epyc12=1; next}
    in_epyc12 && /^    [A-Za-z0-9._-]+:/ && $0 !~ /^    epyc12:/ {in_epyc12=0}
    in_epyc12 && /^      - / {sub(/^      - /, "", $0); print $0}
  ' "$manifest"
}

fleet_sync_issue_lines=""
add_fleet_issue() {
  local msg="$1"
  fleet_sync_issue_lines="${fleet_sync_issue_lines}- ${msg}\n"
}

parse_fleet_ssh_targets() {
  local cfg="$1"
  [[ -f "$cfg" ]] || return 0
  awk '
    /^hosts:/ {in_hosts=1; next}
    in_hosts && /^[^[:space:]]/ {in_hosts=0}
    in_hosts && /^  [A-Za-z0-9._-]+:$/ {
      host=$1
      gsub(":", "", host)
      next
    }
    in_hosts && /ssh:[[:space:]]*"/ {
      if (match($0, /\"([^\"]+)\"/)) {
        print host "|" substr($0, RSTART + 1, RLENGTH - 2)
      }
    }
  ' "$cfg"
}

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
    grep -v "Feature-Key:" | grep -v "^\[" | grep -v "^Merge" | wc -l || true)
  [[ -z "$commits_without_fk" ]] && commits_without_fk="0"
  commits_without_fk=$(echo "$commits_without_fk" | tr -d ' ')
  missing_feature_key[$repo_name]=$commits_without_fk
  total_missing_fk=$((total_missing_fk + commits_without_fk))

  # 3. Agent: trailer compliance
  commits_without_agent=$(gh api "repos/$repo/commits?sha=master&per_page=20" \
    --jq '.[].commit.message' 2>/dev/null | \
    grep -v "Agent:" | grep -v "^\[" | grep -v "^Merge" | grep -v "github-actions" | wc -l || true)
  [[ -z "$commits_without_agent" ]] && commits_without_agent="0"
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

# Fleet Sync V2.1 contract evaluation
fleet_sync_spec_present=0
fleet_sync_manifest_present=0
mcp_tools_manifest_present=0
fleet_sync_skill_stubs_missing=0
fleet_sync_local_first_declared=0
fleet_sync_epyc12_required_count=0
fleet_sync_forbidden_required_count=0
fleet_sync_script_present=0
fleet_sync_tool_version_drift_hosts=0
fleet_sync_tool_health_stale_hosts=0
fleet_sync_dolt_stale_hosts=0
fleet_sync_hosts_checked=0
fleet_sync_hosts_missing_reports=0
fleet_sync_runtime_service_count_epyc12=-1

if [[ -f "$FLEET_SYNC_SPEC_PRIMARY" || -f "$FLEET_SYNC_SPEC_LEGACY" ]]; then
  fleet_sync_spec_present=1
else
  add_fleet_issue "Missing docs/FLEET_SYNC_SPEC.md (or legacy docs/FLEET_SYNC_SPEC_V2.md)"
fi
[[ -f "$FLEET_SYNC_MANIFEST" ]] && fleet_sync_manifest_present=1 || add_fleet_issue "Missing configs/fleet-sync.manifest.yaml"
[[ -f "$MCP_TOOLS_MANIFEST" ]] && mcp_tools_manifest_present=1 || add_fleet_issue "Missing configs/mcp-tools.yaml"
[[ -x "$FLEET_SYNC_SCRIPT" ]] && fleet_sync_script_present=1 || add_fleet_issue "Missing executable scripts/dx-mcp-tools-sync.sh"

for skill_stub in "${FLEET_SYNC_SKILL_STUBS[@]}"; do
  if [[ ! -f "$skill_stub" ]]; then
    fleet_sync_skill_stubs_missing=$((fleet_sync_skill_stubs_missing + 1))
  fi
done
[[ "$fleet_sync_skill_stubs_missing" -eq 0 ]] || add_fleet_issue "Missing ${fleet_sync_skill_stubs_missing} Fleet Sync skill stubs"

if [[ -f "$FLEET_SYNC_MANIFEST" ]]; then
  manifest_required_cap="$(awk '/^[[:space:]]*epyc12_max_always_on_services:[[:space:]]*[0-9]+/{print $2; exit}' "$FLEET_SYNC_MANIFEST" 2>/dev/null || true)"
  if [[ -n "$manifest_required_cap" && "$manifest_required_cap" =~ ^[0-9]+$ ]]; then
    FLEET_SYNC_EPYC12_REQUIRED_MAX="$manifest_required_cap"
  fi

  grep -Eq '^[[:space:]]*execution:[[:space:]]*local_first([[:space:]]|$)' "$FLEET_SYNC_MANIFEST" && fleet_sync_local_first_declared=1
  [[ "$fleet_sync_local_first_declared" -eq 1 ]] || add_fleet_issue "Manifest does not declare execution: local_first"

  required_services="$(extract_epyc12_required_services "$FLEET_SYNC_MANIFEST" || true)"
  if [[ -n "$required_services" ]]; then
    fleet_sync_epyc12_required_count=$(echo "$required_services" | sed '/^$/d' | wc -l | tr -d ' ')
    fleet_sync_forbidden_required_count=$(echo "$required_services" | grep -Eic "$FLEET_SYNC_FORBIDDEN_REQUIRED_REGEX" || true)
  fi
fi

fleet_sync_service_cap_ok=0
fleet_sync_forbidden_required_ok=0
if [[ -f "$FLEET_SYNC_MANIFEST" ]]; then
  if [[ "$fleet_sync_epyc12_required_count" -le "$FLEET_SYNC_EPYC12_REQUIRED_MAX" ]]; then
    fleet_sync_service_cap_ok=1
  else
    add_fleet_issue "epyc12 required services (${fleet_sync_epyc12_required_count}) exceed cap (${FLEET_SYNC_EPYC12_REQUIRED_MAX})"
  fi

  if [[ "$fleet_sync_forbidden_required_count" -eq 0 ]]; then
    fleet_sync_forbidden_required_ok=1
  else
    add_fleet_issue "Required services include forbidden gateway components (supergateway/mcp-proxy)"
  fi
else
  add_fleet_issue "Cannot validate required service constraints without fleet manifest"
fi

# Best-effort cross-VM Fleet Sync checks (version drift, tool health, Dolt freshness)
if [[ -f "$FLEET_HOSTS_CONFIG" && "$fleet_sync_script_present" -eq 1 ]]; then
  while IFS='|' read -r host_name ssh_target; do
    [[ -z "$host_name" || -z "$ssh_target" ]] && continue
    fleet_sync_hosts_checked=$((fleet_sync_hosts_checked + 1))

    report_cmd='test -x "$HOME/agent-skills/scripts/dx-mcp-tools-sync.sh" && "$HOME/agent-skills/scripts/dx-mcp-tools-sync.sh" --report-lines'
    report_lines="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$ssh_target" "$report_cmd" 2>/dev/null || true)"

    if [[ -z "$report_lines" ]]; then
      fleet_sync_hosts_missing_reports=$((fleet_sync_hosts_missing_reports + 1))
      add_fleet_issue "No Fleet Sync report from ${host_name} (${ssh_target})"
      continue
    fi

    host_tool_drift=0
    host_tool_health_stale=0
    host_dolt_stale=0
    meta_seen=0

    while IFS='|' read -r row_kind c1 c2 c3 c4 c5 c6 c7; do
      [[ -z "$row_kind" ]] && continue
      if [[ "$row_kind" == "meta" ]]; then
        meta_seen=1
        # meta|generated_at_epoch|dolt_ok|dolt_last_ok_epoch
        dolt_ok="$c2"
        dolt_last_ok_epoch="$c3"
        now_epoch="$(date -u +%s)"
        max_dolt_stale_seconds=$((FLEET_SYNC_MAX_DOLT_STALE_MINUTES * 60))
        if [[ "$dolt_ok" != "true" ]]; then
          host_dolt_stale=1
        elif [[ -n "$dolt_last_ok_epoch" && "$dolt_last_ok_epoch" =~ ^[0-9]+$ ]]; then
          if (( now_epoch - dolt_last_ok_epoch > max_dolt_stale_seconds )); then
            host_dolt_stale=1
          fi
        fi
        continue
      fi

      if [[ "$row_kind" != "tool" ]]; then
        continue
      fi

      # tool|name|expected|detected|healthy|last_ok_epoch|last_fail_epoch|error_summary
      tool_name="$c1"
      expected_version="$c2"
      detected_version="$c3"
      healthy="$c4"
      last_ok_epoch="$c5"

      if [[ -n "$expected_version" && -n "$detected_version" && "$expected_version" != "$detected_version" ]]; then
        host_tool_drift=1
        add_fleet_issue "Version drift on ${host_name} (${tool_name}: expected ${expected_version}, got ${detected_version})"
      fi

      now_epoch="$(date -u +%s)"
      max_tool_stale_seconds=$((FLEET_SYNC_MAX_TOOL_STALE_HOURS * 3600))
      if [[ "$healthy" != "true" ]]; then
        host_tool_health_stale=1
      elif [[ -n "$last_ok_epoch" && "$last_ok_epoch" =~ ^[0-9]+$ ]]; then
        if (( now_epoch - last_ok_epoch > max_tool_stale_seconds )); then
          host_tool_health_stale=1
        fi
      else
        host_tool_health_stale=1
      fi
    done <<< "$report_lines"

    if [[ "$meta_seen" -eq 0 ]]; then
      host_dolt_stale=1
      add_fleet_issue "Missing Fleet Sync meta row from ${host_name}"
    fi

    [[ "$host_tool_drift" -eq 0 ]] || fleet_sync_tool_version_drift_hosts=$((fleet_sync_tool_version_drift_hosts + 1))
    [[ "$host_tool_health_stale" -eq 0 ]] || fleet_sync_tool_health_stale_hosts=$((fleet_sync_tool_health_stale_hosts + 1))
    [[ "$host_dolt_stale" -eq 0 ]] || fleet_sync_dolt_stale_hosts=$((fleet_sync_dolt_stale_hosts + 1))
  done <<< "$(parse_fleet_ssh_targets "$FLEET_HOSTS_CONFIG")"

  if [[ "$fleet_sync_hosts_checked" -eq 0 ]]; then
    add_fleet_issue "No hosts parsed from configs/fleet_hosts.yaml for Fleet Sync audit checks"
  fi
else
  add_fleet_issue "Skipping cross-VM Fleet Sync checks (missing fleet_hosts.yaml or dx-mcp-tools-sync.sh)"
fi

# Runtime service count guardrail on epyc12
fleet_sync_runtime_service_cap_ok=0
if [[ -f "$FLEET_HOSTS_CONFIG" ]]; then
  epyc12_ssh_target="$(parse_fleet_ssh_targets "$FLEET_HOSTS_CONFIG" | awk -F'|' '$1=="epyc12"{print $2; exit}')"
  if [[ -n "$epyc12_ssh_target" ]]; then
    runtime_service_count_cmd='count=0; for s in beads-dolt.service opencode.service opencode-server.service litellm.service supergateway.service mcp-proxy.service; do systemctl --user is-active --quiet "$s" && count=$((count+1)); done; echo "$count"'
    runtime_service_count_raw="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$epyc12_ssh_target" "$runtime_service_count_cmd" 2>/dev/null || true)"
    runtime_service_count_raw="$(echo "$runtime_service_count_raw" | tr -d '[:space:]')"
    if [[ "$runtime_service_count_raw" =~ ^[0-9]+$ ]]; then
      fleet_sync_runtime_service_count_epyc12="$runtime_service_count_raw"
      if [[ "$fleet_sync_runtime_service_count_epyc12" -le "$FLEET_SYNC_RUNTIME_SERVICE_CAP" ]]; then
        fleet_sync_runtime_service_cap_ok=1
      else
        add_fleet_issue "epyc12 runtime DX services (${fleet_sync_runtime_service_count_epyc12}) exceed cap (${FLEET_SYNC_RUNTIME_SERVICE_CAP})"
      fi
    else
      add_fleet_issue "Unable to read runtime DX service count on epyc12"
    fi
  else
    add_fleet_issue "epyc12 ssh target missing in configs/fleet_hosts.yaml"
  fi
else
  add_fleet_issue "configs/fleet_hosts.yaml missing; cannot check epyc12 runtime service count"
fi

fleet_sync_tool_drift_ok=0
fleet_sync_dolt_fresh_ok=0
fleet_sync_tool_health_ok=0
[[ "$fleet_sync_tool_version_drift_hosts" -eq 0 ]] && fleet_sync_tool_drift_ok=1 || add_fleet_issue "Tool version drift detected on ${fleet_sync_tool_version_drift_hosts} host(s)"
[[ "$fleet_sync_dolt_stale_hosts" -eq 0 ]] && fleet_sync_dolt_fresh_ok=1 || add_fleet_issue "Dolt sync freshness/connectivity issues on ${fleet_sync_dolt_stale_hosts} host(s)"
[[ "$fleet_sync_tool_health_stale_hosts" -eq 0 ]] && fleet_sync_tool_health_ok=1 || add_fleet_issue "Tool health stale/failing on ${fleet_sync_tool_health_stale_hosts} host(s)"

fleet_sync_reports_ok=0
if [[ "$fleet_sync_hosts_checked" -gt 0 && "$fleet_sync_hosts_missing_reports" -eq 0 ]]; then
  fleet_sync_reports_ok=1
else
  add_fleet_issue "Missing Fleet Sync reports on ${fleet_sync_hosts_missing_reports}/${fleet_sync_hosts_checked} host(s)"
fi

fleet_sync_total_checks=13
fleet_sync_passed_checks=$(( \
  fleet_sync_spec_present + \
  fleet_sync_manifest_present + \
  mcp_tools_manifest_present + \
  (fleet_sync_skill_stubs_missing == 0 ? 1 : 0) + \
  fleet_sync_local_first_declared + \
  fleet_sync_service_cap_ok + \
  fleet_sync_forbidden_required_ok + \
  fleet_sync_script_present + \
  fleet_sync_reports_ok + \
  fleet_sync_tool_drift_ok + \
  fleet_sync_dolt_fresh_ok + \
  fleet_sync_tool_health_ok + \
  fleet_sync_runtime_service_cap_ok \
))
fleet_sync_failed_checks=$((fleet_sync_total_checks - fleet_sync_passed_checks))

# Generate output
output=""

if [[ "$OUTPUT_FORMAT" == "markdown" ]]; then
  output="## V8 Invariant Audit
Generated: $TS
Lookback: ${LOOKBACK_DAYS} days

### Summary
| Metric | Count | Status |
|--------|-------|--------|
| Rescue branch events (${LOOKBACK_DAYS}d) | $total_rescue | $([ $total_rescue -eq 0 ] && echo '✅ OK' || echo '⚠️ VIOLATION') |
| Commits missing Feature-Key | $total_missing_fk | $([ $total_missing_fk -lt 5 ] && echo '✅ OK' || echo '⚠️ CHECK') |
| Commits missing Agent: trailer | $total_missing_agent | $([ $total_missing_agent -lt 5 ] && echo '✅ OK' || echo '⚠️ CHECK') |
| PRs with auto-merge enabled | $total_auto_merge | $([ $total_auto_merge -eq 0 ] && echo '✅ OK' || echo '❌ VIOLATION') |
| Skill Drift (missing files) | $total_skill_drift | $([ $total_skill_drift -eq 0 ] && echo '✅ OK' || echo '⚠️ DRIFT') |
| Fleet Sync V2.1 contract | ${fleet_sync_passed_checks}/${fleet_sync_total_checks} | $([ "$fleet_sync_failed_checks" -eq 0 ] && echo '✅ OK' || echo '⚠️ REVIEW') |
| Fleet Sync reports coverage | ${fleet_sync_hosts_checked}-${fleet_sync_hosts_missing_reports} / ${fleet_sync_hosts_checked} hosts | $([ "$fleet_sync_reports_ok" -eq 1 ] && echo '✅ OK' || echo '⚠️ PARTIAL') |
| Fleet Sync tool drift hosts | ${fleet_sync_tool_version_drift_hosts} | $([ "$fleet_sync_tool_drift_ok" -eq 1 ] && echo '✅ OK' || echo '⚠️ DRIFT') |
| Fleet Sync Dolt stale hosts | ${fleet_sync_dolt_stale_hosts} | $([ "$fleet_sync_dolt_fresh_ok" -eq 1 ] && echo '✅ OK' || echo '⚠️ STALE') |
| Fleet Sync tool health stale hosts | ${fleet_sync_tool_health_stale_hosts} | $([ "$fleet_sync_tool_health_ok" -eq 1 ] && echo '✅ OK' || echo '⚠️ FAILING') |
| epyc12 runtime DX services | ${fleet_sync_runtime_service_count_epyc12} | $([ "$fleet_sync_runtime_service_cap_ok" -eq 1 ] && echo "✅ <=${FLEET_SYNC_RUNTIME_SERVICE_CAP}" || echo "⚠️ >${FLEET_SYNC_RUNTIME_SERVICE_CAP}") |
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
"

  output="${output}
### Fleet Sync V2.1 Review
- Spec present: $([ "$fleet_sync_spec_present" -eq 1 ] && echo '✅' || echo '❌')
- Fleet manifest present: $([ "$fleet_sync_manifest_present" -eq 1 ] && echo '✅' || echo '❌')
- MCP tools manifest present: $([ "$mcp_tools_manifest_present" -eq 1 ] && echo '✅' || echo '❌')
- Skill stubs present: $([ "$fleet_sync_skill_stubs_missing" -eq 0 ] && echo '✅' || echo "❌ (${fleet_sync_skill_stubs_missing} missing)")
- Manifest local-first declaration: $([ "$fleet_sync_local_first_declared" -eq 1 ] && echo '✅' || echo '❌')
- epyc12 required service cap (<=${FLEET_SYNC_EPYC12_REQUIRED_MAX}): $([ "$fleet_sync_service_cap_ok" -eq 1 ] && echo "✅ (${fleet_sync_epyc12_required_count})" || echo "❌ (${fleet_sync_epyc12_required_count})")
- Forbidden required gateway services: $([ "$fleet_sync_forbidden_required_ok" -eq 1 ] && echo '✅ none' || echo '❌ present')
- Sync script present: $([ "$fleet_sync_script_present" -eq 1 ] && echo '✅' || echo '❌')
- Cross-VM reports coverage: $((fleet_sync_hosts_checked - fleet_sync_hosts_missing_reports))/${fleet_sync_hosts_checked}
- Tool version drift hosts: ${fleet_sync_tool_version_drift_hosts}
- Dolt stale hosts: ${fleet_sync_dolt_stale_hosts}
- Tool health stale/failing hosts: ${fleet_sync_tool_health_stale_hosts}
- epyc12 runtime DX services (cap ${FLEET_SYNC_RUNTIME_SERVICE_CAP}): ${fleet_sync_runtime_service_count_epyc12}
"

  if [[ "$fleet_sync_failed_checks" -gt 0 ]]; then
    output="${output}

#### Fleet Sync Findings
$(printf "%b" "$fleet_sync_issue_lines")"
  fi

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
    "skill_drift": $total_skill_drift,
    "fleet_sync_passed_checks": $fleet_sync_passed_checks,
    "fleet_sync_total_checks": $fleet_sync_total_checks,
    "fleet_sync_hosts_checked": $fleet_sync_hosts_checked,
    "fleet_sync_hosts_missing_reports": $fleet_sync_hosts_missing_reports,
    "fleet_sync_tool_version_drift_hosts": $fleet_sync_tool_version_drift_hosts,
    "fleet_sync_dolt_stale_hosts": $fleet_sync_dolt_stale_hosts,
    "fleet_sync_tool_health_stale_hosts": $fleet_sync_tool_health_stale_hosts,
    "fleet_sync_runtime_service_count_epyc12": $fleet_sync_runtime_service_count_epyc12,
    "auto_merge_enabled": $total_auto_merge,
    "stale_prs": $total_stale,
    "draft_prs": $total_draft
  },
  "fleet_sync": {
    "spec_present": $([ "$fleet_sync_spec_present" -eq 1 ] && echo 'true' || echo 'false'),
    "manifest_present": $([ "$fleet_sync_manifest_present" -eq 1 ] && echo 'true' || echo 'false'),
    "mcp_tools_manifest_present": $([ "$mcp_tools_manifest_present" -eq 1 ] && echo 'true' || echo 'false'),
    "skill_stubs_missing": $fleet_sync_skill_stubs_missing,
    "local_first_declared": $([ "$fleet_sync_local_first_declared" -eq 1 ] && echo 'true' || echo 'false'),
    "epyc12_required_service_count": $fleet_sync_epyc12_required_count,
    "epyc12_required_service_cap": $FLEET_SYNC_EPYC12_REQUIRED_MAX,
    "forbidden_required_gateway_count": $fleet_sync_forbidden_required_count,
    "sync_script_present": $([ "$fleet_sync_script_present" -eq 1 ] && echo 'true' || echo 'false'),
    "reports_ok": $([ "$fleet_sync_reports_ok" -eq 1 ] && echo 'true' || echo 'false'),
    "tool_version_drift_hosts": $fleet_sync_tool_version_drift_hosts,
    "dolt_stale_hosts": $fleet_sync_dolt_stale_hosts,
    "tool_health_stale_hosts": $fleet_sync_tool_health_stale_hosts,
    "runtime_service_count_epyc12": $fleet_sync_runtime_service_count_epyc12,
    "runtime_service_cap_epyc12": $FLEET_SYNC_RUNTIME_SERVICE_CAP,
    "passed_checks": $fleet_sync_passed_checks,
    "total_checks": $fleet_sync_total_checks
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
  elif [ "$total_stale" -gt 2 ] || [ "$total_skill_drift" -gt 0 ] || [ "$fleet_sync_failed_checks" -gt 0 ]; then
    status_emoji="⚠️"
    status_text="PR, Skill Drift, or Fleet Sync drift detected"
  fi

  # Build main message (≤300 chars)
  output="${status_emoji} *V8 Weekly Audit* (${LOOKBACK_DAYS}d):
• Rescue events (${LOOKBACK_DAYS}d): ${total_rescue} $([ $total_rescue -eq 0 ] && echo '✅' || echo '❌')
• Auto-merge PRs: ${total_auto_merge} $([ $total_auto_merge -eq 0 ] && echo '✅' || echo '❌')
• Skill Drift: ${total_skill_drift} $([ $total_skill_drift -eq 0 ] && echo '✅' || echo '⚠️')
• Fleet Sync V2.1: ${fleet_sync_passed_checks}/${fleet_sync_total_checks} $([ "$fleet_sync_failed_checks" -eq 0 ] && echo '✅' || echo '⚠️')
• Fleet Sync hosts: $((fleet_sync_hosts_checked - fleet_sync_hosts_missing_reports))/${fleet_sync_hosts_checked} | Drift hosts: ${fleet_sync_tool_version_drift_hosts}
• Dolt stale hosts: ${fleet_sync_dolt_stale_hosts} | Tool health stale: ${fleet_sync_tool_health_stale_hosts}
• Stale PRs: ${total_stale} | Drafts: ${total_draft}"

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

  if [ "$fleet_sync_failed_checks" -gt 0 ] && [[ -n "$fleet_sync_issue_lines" ]]; then
    output="${output}
---THREAD---
*Fleet Sync V2.1 Findings:*"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      output="${output}
${line}"
    done <<< "$(printf "%b" "$fleet_sync_issue_lines")"
  fi
fi

# Output
if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$output" > "$OUTPUT_FILE"
  echo "Audit written to: $OUTPUT_FILE" >&2
else
  echo "$output"
fi
