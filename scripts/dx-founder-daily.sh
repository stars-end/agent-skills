#!/usr/bin/env bash
#
# dx-founder-daily.sh - Founder Daily Briefing Data Gatherer
#
# Purpose: Gather high-priority tasks from BEADS and GitHub Actions for founder briefing
# Schedule: Daily at 9 AM PT M-F (via cron)
# Bead: bd-lsxp.3
#
# Dependencies:
#   - Beads source at ~/.beads-runtime/.beads (canonical `bdx` coordination path with hub-spoke Dolt SQL backend).
#     SQLite/JSONL are compatibility fallbacks only and must be explicitly enabled.
#   - GitHub CLI (gh) authenticated
#   - bv CLI for robot alerts/drift check
#   - jq for JSON manipulation
#
# Output: JSON file with consolidated data for formatting

set -euo pipefail

# Configuration
BEADS_DIR="${BEADS_DIR:-${HOME}/.beads-runtime/.beads}"
BEADS_DB="${BEADS_DIR}/beads.db"
BEADS_ISSUES_JSONL="${BEADS_DIR}/issues.jsonl"
GH_REPO="stars-end/prime-radiant-ai"
ALLOW_BEADS_LEGACY_SOURCE="${ALLOW_BEADS_LEGACY_SOURCE:-0}"
TEMP_DIR=$(mktemp -d)
OUTPUT_FILE="${TEMP_DIR}/founder-daily-data.json"
LOG_FILE="${TEMP_DIR}/founder-daily.log"
BEADS_SOURCE="auto"
BEADS_CLI_OPEN_CACHE=""
QUERY_SOURCE_RESOLVED="false"
P0_ISSUES_JSON="[]"
P1_ISSUES_JSON="[]"
BLOCKING_ISSUES_JSON="[]"
STALE_ISSUES_JSON="[]"
ALERTS_JSON='{"alerts": [], "summary": {"total": 0, "critical": 0, "warning": 0, "info": 0}}'
CRITICAL_COUNT=0
DRIFT_STATUS="unknown"
FAILED_RUNS_JSON="[]"
FAILED_COUNT=0
WORKFLOW_HEALTH_JSON="[]"
STALE_PRS_COUNT=0
BACKLOG_COUNT=0
RESCUE_COUNT=0

# Founder pipeline telemetry (machine-readable classification for founders + digests)
PIPELINE_STARTED_AT="$(date -u +%s)"
PIPELINE_STARTED_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
PIPELINE_STATUS="ok"
PIPELINE_REASON="none"
PIPELINE_SOURCE="auto"
PIPELINE_ERROR=""

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG_FILE"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >&2
}

error() {
  echo -e "${RED}❌ $1${NC}" >> "$LOG_FILE"
  echo -e "${RED}❌ $1${NC}" >&2
}

success() {
  echo -e "${GREEN}✅ $1${NC}" >> "$LOG_FILE"
  echo -e "${GREEN}✅ $1${NC}" >&2
}

warn() {
  echo -e "${YELLOW}⚠️  $1${NC}" >> "$LOG_FILE"
  echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

pipeline_fail() {
  local reason="$1"
  local context="${2:-}"
  PIPELINE_STATUS="failed"
  PIPELINE_REASON="$reason"
  PIPELINE_ERROR="${context:-$PIPELINE_ERROR}"
}

pipeline_warn() {
  local reason="$1"
  local context="${2:-}"
  if [[ "$PIPELINE_STATUS" == "failed" ]]; then
    return
  fi
  PIPELINE_STATUS="warning"
  PIPELINE_REASON="$reason"
  PIPELINE_ERROR="${context:-$PIPELINE_ERROR}"
}

mark_pipeline_resolved() {
  if [[ "$PIPELINE_STATUS" == "failed" ]]; then
    return
  fi
  if [[ "$PIPELINE_STATUS" == "warning" ]]; then
    return
  fi
  PIPELINE_STATUS="ok"
  PIPELINE_REASON="none"
}

finalize_source() {
  PIPELINE_SOURCE="$1"
}

build_pipeline_payload() {
  local status="$1"
  local reason="$2"
  local source="$3"
  local context="${4:-}"

  local now_ts completed_ts age_ms
  now_ts="$(date -u +%s)"
  completed_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  age_ms=$(( (now_ts - PIPELINE_STARTED_AT) * 1000 ))

  jq -n \
    --arg timestamp "$completed_ts" \
    --arg started_at "$PIPELINE_STARTED_TS" \
    --arg source "$source" \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg context "${context:-$PIPELINE_ERROR}" \
    --argjson duration_ms "$age_ms" \
    --argjson p0 "${P0_ISSUES_JSON:-[]}" \
    --argjson p1 "${P1_ISSUES_JSON:-[]}" \
    --argjson blocking "${BLOCKING_ISSUES_JSON:-[]}" \
    --argjson stale "${STALE_ISSUES_JSON:-[]}" \
    --argjson alerts "${ALERTS_JSON:-[]}" \
    --argjson critical "$CRITICAL_COUNT" \
    --arg drift "$DRIFT_STATUS" \
    --argjson failed "${FAILED_RUNS_JSON:-[]}" \
    --argjson failed_count "$FAILED_COUNT" \
    --argjson stale_prs_count "$STALE_PRS_COUNT" \
    --argjson backlog_count "$BACKLOG_COUNT" \
    --argjson rescue_count "$RESCUE_COUNT" \
    --argjson workflow_health "${WORKFLOW_HEALTH_JSON:-[]}" \
    '{
      timestamp: $timestamp,
      founder_pipeline: {
        status: $status,
        source: $source,
        reason: $reason,
        reason_context: $context,
        duration_ms: $duration_ms,
        started_at: $started_at
      },
      beads: {
        p0_issues: $p0,
        p1_issues: $p1,
        blocking_issues: $blocking,
        stale_issues: $stale,
        backlog_count: $backlog_count,
        robot_alerts: {
          critical: $critical,
          alerts: $alerts
        },
        drift_status: $drift
      },
      github: {
        failed_runs: $failed,
        failed_count: $failed_count,
        stale_prs_count: $stale_prs_count,
        rescue_count: $rescue_count,
        workflow_health: $workflow_health
      }
    }' > "$OUTPUT_FILE"
}

# Cleanup on exit
cleanup() {
  if [ -d "$TEMP_DIR" ]; then
    if [[ -f "$LOG_FILE" ]]; then
      cat "$LOG_FILE" 2>/dev/null >&2 || true
    fi
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

# Check dependencies
check_dependencies() {
  local missing=()

  if ! command -v jq >/dev/null 2>&1; then
    missing+=("jq")
  fi
  if ! command -v bdx >/dev/null 2>&1; then
    if [ "$ALLOW_BEADS_LEGACY_SOURCE" = "1" ]; then
      warn "bdx CLI not found; compatibility fallback mode enabled via ALLOW_BEADS_LEGACY_SOURCE=1"
    else
      error "bdx CLI not found. Active Beads contract requires the coordination wrapper."
      error "Set ALLOW_BEADS_LEGACY_SOURCE=1 temporarily if explicit legacy compatibility mode is required."
      return 1
    fi
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing dependencies: ${missing[*]}"
    return 1
  fi

  if [ "$ALLOW_BEADS_LEGACY_SOURCE" = "1" ] && ! command -v sqlite3 >/dev/null 2>&1; then
    warn "sqlite3 not found; legacy sqlite fallback unavailable"
  fi

  return 0
}

query_cli_open_issues() {
  if [ -n "$BEADS_CLI_OPEN_CACHE" ]; then
    echo "$BEADS_CLI_OPEN_CACHE"
    return 0
  fi

  if ! command -v bdx >/dev/null 2>&1; then
    return 1
  fi

  local raw
  raw="$(cd "${HOME}" && bdx list --json --status open --limit 0 2>>"$LOG_FILE" || true)"
  if [ -z "$raw" ] || ! jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1; then
    return 1
  fi

  BEADS_CLI_OPEN_CACHE="$raw"
  echo "$raw"
  return 0
}

query_jsonl_open_issues() {
  if [[ ! -f "$BEADS_ISSUES_JSONL" ]]; then
    echo "[]"
    return 1
  fi

  local raw
  raw="$(jq -c '[inputs | select((.status // "open") == "open") | select(((.issue_type // .type // "") != "epic")]' "$BEADS_ISSUES_JSONL" 2>>"$LOG_FILE" || true)"
  if [ -z "$raw" ]; then
    echo "[]"
    return 1
  fi

  echo "$raw"
  return 0
}

query_source() {
  if [[ "$QUERY_SOURCE_RESOLVED" == "true" ]]; then
    return 0
  fi

  QUERY_SOURCE_RESOLVED="true"

  if query_cli_open_issues >/dev/null 2>&1; then
    BEADS_SOURCE="cli"
    finalize_source "cli"
    return 0
  fi

  warn "Dolt CLI unavailable; checking compatibility source fallback."

  if [[ "$ALLOW_BEADS_LEGACY_SOURCE" != "1" ]]; then
    BEADS_SOURCE="missing"
    pipeline_fail "beads_source_missing" "bdx CLI unavailable and compatibility source disabled"
    return 1
  fi

  if [[ -f "$BEADS_DB" ]]; then
    if sqlite3 "$BEADS_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='issues';" >/dev/null 2>&1; then
      BEADS_SOURCE="sqlite"
      finalize_source "sqlite"
      return 0
    fi

    # Legacy DB exists but schema is incomplete for issue extraction.
    if [[ -f "$BEADS_ISSUES_JSONL" ]]; then
      BEADS_SOURCE="jsonl"
      pipeline_warn "legacy_db_no_issues_table" "legacy SQLite exists but missing issues table; fallback to JSONL compatibility"
      finalize_source "jsonl"
      return 0
    fi

    BEADS_SOURCE="bad-sqlite"
    pipeline_fail "legacy_db_no_issues_table" "legacy SQLite database exists but no issues table and no JSONL fallback"
    return 1
  fi

  if [[ -f "$BEADS_ISSUES_JSONL" ]]; then
    BEADS_SOURCE="jsonl"
    pipeline_warn "legacy_jsonl_fallback" "fallback to JSONL compatibility source"
    finalize_source "jsonl"
    return 0
  fi

  BEADS_SOURCE="missing"
  pipeline_fail "beads_source_missing" "no usable Beads source found"
  return 1
}

require_active_dolt_source() {
  if [ "$BEADS_SOURCE" = "cli" ]; then
    mark_pipeline_resolved
    return 0
  fi

  case "$BEADS_SOURCE" in
    sqlite|jsonl)
      if [ "$ALLOW_BEADS_LEGACY_SOURCE" = "1" ]; then
        # Compatibility sources are accepted with warning/fallback semantics.
        return 0
      fi
      ;;
  esac

  error "Unable to resolve canonical Beads source (bdx CLI required)."
  error "Run from an environment where Beads runtime + SQL service are available."
  error "Set ALLOW_BEADS_LEGACY_SOURCE=1 only for compatibility troubleshooting."
  pipeline_fail "${PIPELINE_REASON:-beads_source_missing}" "${PIPELINE_ERROR:-expected CLI but got ${BEADS_SOURCE}}"
  return 1
}

# Query BEADS for P0 issues
query_p0_issues() {
  log "Querying BEADS for P0 issues..."

  query_source || return 1

  if [ "$BEADS_SOURCE" = "sqlite" ]; then
    sqlite3 "$BEADS_DB" "
      SELECT json_group_array(
        json_object(
          'id', id,
          'title', title,
          'priority', cast(priority as text),
          'status', status,
          'issue_type', issue_type,
          'updated_at', updated_at
        )
      )
      FROM issues
      WHERE priority = 0 AND status = 'open' AND issue_type != 'epic'
      ORDER BY updated_at DESC
      LIMIT 10;
    " 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "cli" ]; then
    query_cli_open_issues | jq -c '[
      .[]
      | select((.status // "open") == "open")
      | select(((.issue_type // .type // "") != "epic"))
      | select((.priority // "P99" | tostring | ascii_downcase) | test("^p?0$") )
      | {id: .id, title: .title, priority: (.priority // ""), status: .status, issue_type: (.issue_type // .type // ""), updated_at: .updated_at}
    ] | sort_by(.updated_at // "") | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "jsonl" ]; then
    query_jsonl_open_issues | jq -c '[
      .[]
      | select((.priority // "P99" | tostring | ascii_downcase) | test("^p?0$") )
      | {id: .id, title: .title, priority: (.priority // ""), status: .status, issue_type: (.issue_type // .type // ""), updated_at: .updated_at}
    ] | sort_by(.updated_at // "") | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  echo "[]"; return 0
}

# Query BEADS for P1 issues
query_p1_issues() {
  log "Querying BEADS for P1 issues..."

  query_source || return 1

  if [ "$BEADS_SOURCE" = "sqlite" ]; then
    sqlite3 "$BEADS_DB" "
      SELECT json_group_array(
        json_object(
          'id', id,
          'title', title,
          'priority', cast(priority as text),
          'status', status,
          'issue_type', issue_type,
          'updated_at', updated_at
        )
      )
      FROM issues
      WHERE priority = 1 AND status = 'open' AND issue_type != 'epic'
      ORDER BY updated_at DESC
      LIMIT 10;
    " 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "cli" ]; then
    query_cli_open_issues | jq -c '[
      .[]
      | select((.status // "open") == "open")
      | select(((.issue_type // .type // "") != "epic"))
      | select((.priority // "P99" | tostring | ascii_downcase) | test("^p?1$") )
      | {id: .id, title: .title, priority: (.priority // ""), status: .status, issue_type: (.issue_type // .type // ""), updated_at: .updated_at}
    ] | sort_by(.updated_at // "") | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "jsonl" ]; then
    query_jsonl_open_issues | jq -c '[
      .[]
      | select((.priority // "P99" | tostring | ascii_downcase) | test("^p?1$") )
      | {id: .id, title: .title, priority: (.priority // ""), status: .status, issue_type: (.issue_type // .type // ""), updated_at: .updated_at}
    ] | sort_by(.updated_at // "") | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  echo "[]"; return 0
}

# Query BEADS for blocking issues
query_blocking_issues() {
  log "Querying BEADS for blocking issues..."

  query_source || return 1

  if [ "$BEADS_SOURCE" = "sqlite" ]; then
    sqlite3 "$BEADS_DB" "
      SELECT json_group_array(
        json_object(
          'id', id,
          'title', title,
          'priority', cast(priority as text),
          'status', status,
          'blocked_count', blocked_count
        )
      )
      FROM (
        SELECT
          i.id,
          i.title,
          i.priority,
          i.status,
          (SELECT COUNT(*) FROM dependencies d
           WHERE d.depends_on_id = i.id AND d.type = 'blocks') as blocked_count
        FROM issues i
        WHERE i.status = 'open' AND i.issue_type != 'epic'
          AND (SELECT COUNT(*) FROM dependencies d
               WHERE d.depends_on_id = i.id AND d.type = 'blocks') > 0
        ORDER BY i.priority DESC, blocked_count DESC
        LIMIT 10
      );
    " 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "cli" ]; then
    query_cli_open_issues | jq -c '[
      .[]
      | select((.status // "open") == "open")
      | select(((.issue_type // .type // "") != "epic"))
      | select((.dependency_count // 0) | tonumber? > 0)
      | . as $issue
      | {
          id: $issue.id,
          title: $issue.title,
          priority: ($issue.priority // ""),
          status: $issue.status,
          blocked_count: ($issue.dependency_count // 0)
        }
    ] | sort_by(.blocked_count | tonumber?) | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "jsonl" ]; then
    query_jsonl_open_issues | jq -c '[
      .[]
      | select((.dependency_count // 0) | tonumber? > 0)
      | . as $issue
      | {
          id: $issue.id,
          title: $issue.title,
          priority: ($issue.priority // ""),
          status: $issue.status,
          blocked_count: ($issue.dependency_count // 0)
        }
    ] | sort_by(.blocked_count | tonumber?) | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  echo "[]"; return 0
}

# Query BEADS for stale issues (>14 days)
query_stale_issues() {
  log "Querying BEADS for stale issues..."

  query_source || return 1

  if [ "$BEADS_SOURCE" = "sqlite" ]; then
    sqlite3 "$BEADS_DB" "
      SELECT json_group_array(
        json_object(
          'id', id,
          'title', title,
          'updated_at', updated_at,
          'days_stale', days_stale
        )
      )
      FROM (
        SELECT 
          id,
          title,
          updated_at,
          cast(julianday('now') - julianday(updated_at) as integer) as days_stale
        FROM issues
        WHERE status = 'open' AND issue_type != 'epic'
          AND cast(julianday('now') - julianday(updated_at) as integer) > 14
        ORDER BY days_stale DESC
        LIMIT 10
      );
    " 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "cli" ]; then
    local now
    now=$(date -u +%s)
    query_cli_open_issues | jq --argjson now "$now" -c '[
      .[]
      | select((.status // "open") == "open")
      | select(((.issue_type // .type // "") != "epic"))
      | . as $issue
      | (($now - (($issue.updated_at // "1970-01-01T00:00:00Z") | fromdate? // 0)) as $age
         | select($age > 1209600)
         | {
             id: $issue.id,
             title: $issue.title,
             updated_at: $issue.updated_at,
             days_stale: ($age / 86400 | floor)
           })
    ] | sort_by(.days_stale) | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "jsonl" ]; then
    local now
    now=$(date -u +%s)
    query_jsonl_open_issues | jq --argjson now "$now" -c '[
      .[]
      | . as $issue
      | (($now - (($issue.updated_at // "1970-01-01T00:00:00Z") | fromdate? // 0)) as $age
         | select($age > 1209600)
         | {
             id: $issue.id,
             title: $issue.title,
             updated_at: $issue.updated_at,
             days_stale: ($age / 86400 | floor)
           })
    ] | sort_by(.days_stale) | reverse | .[:10]' 2>>"$LOG_FILE" || echo "[]"
    return 0
  fi

  echo "[]"; return 0
}

# Get robot alerts from bv
get_robot_alerts() {
  log "Getting robot alerts from bv..."

  if ! command -v bv >/dev/null 2>&1; then
    warn "bv CLI not found, skipping robot alerts"
    echo '{"alerts": [], "summary": {"total": 0, "critical": 0, "warning": 0, "info": 0}}'
    return 0
  fi

  BEADS_DIR="$BEADS_DIR" bv --robot-alerts --severity=critical 2>>"$LOG_FILE" || \
    echo '{"alerts": [], "summary": {"total": 0, "critical": 0, "warning": 0, "info": 0}}'
}

# Query Stale PRs (> 48h)
query_stale_prs() {
  log "Querying Stale PRs (> 48h)..."
  # define stale date (48h ago)
  local stale_date
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stale_date=$(date -v-48H +%Y-%m-%dT%H:%M:%SZ)
  else
    stale_date=$(date -d "48 hours ago" +%Y-%m-%dT%H:%M:%SZ)
  fi
  
  gh pr list --repo "$GH_REPO" --repo stars-end/agent-skills --repo stars-end/affordabot --repo stars-end/llm-common \
    --search "created:<$stale_date state:open" \
    --json number,title,createdAt,url \
    --limit 10 2>>"$LOG_FILE" || echo "[]"
}

# Query Backlog Size (Open Beads)
query_backlog_count() {
  log "Querying Backlog Size..."
  query_source || return 1

  if [ "$BEADS_SOURCE" = "sqlite" ]; then
    sqlite3 "$BEADS_DB" "SELECT count(*) FROM issues WHERE status = 'open';" 2>>"$LOG_FILE" || echo "0"
    return 0
  fi

  if [ "$BEADS_SOURCE" = "cli" ]; then
    query_cli_open_issues | jq -c 'map(select((.status // "open") == "open" and ((.issue_type // .type // "") != "epic"))) | length' 2>>"$LOG_FILE" | tr -d '\n' | tr -dc '0-9'
    return 0
  fi

  if [ "$BEADS_SOURCE" = "jsonl" ]; then
    query_jsonl_open_issues | jq -c 'length' 2>>"$LOG_FILE" | tr -d '\n' | tr -dc '0-9'
    return 0
  fi

  echo "0"; return 0
}

# Query Rescue PRs
query_rescue_prs() {
  log "Querying Rescue PRs..."
  gh pr list --repo "$GH_REPO" --repo stars-end/agent-skills --repo stars-end/affordabot --repo stars-end/llm-common \
    --search "label:wip/rescue state:open" \
    --json number,title,url \
    --limit 5 2>>"$LOG_FILE" || echo "[]"
}

# Check drift status
check_drift() {
  log "Checking drift status..."

  if ! command -v bv >/dev/null 2>&1; then
    warn "bv CLI not found, drift status unknown"
    echo "unknown"
    return 0
  fi

  BEADS_DIR="$BEADS_DIR" bv --check-drift >/dev/null 2>&1
  local exit_code=$?

  case $exit_code in
    0) echo "ok" ;;
    1) echo "critical" ;;
    2) echo "warning" ;;
    *) echo "unknown" ;;
  esac
}

# Query GitHub for failed runs (last 24h)
query_github_failed() {
  log "Querying GitHub for failed runs..."

  if ! command -v gh >/dev/null 2>&1; then
    warn "gh CLI not found, skipping GitHub queries"
    echo "[]"
    return 0
  fi

  gh run list --repo "$GH_REPO" \
    --json conclusion,createdAt,workflowName,databaseId \
    --limit 50 \
    --jq '[.[] | select(.conclusion != "success" and (.createdAt | fromdateiso8601) > now - 86400) | {workflow: .workflowName, created: .createdAt, id: .databaseId, url: ("https://github.com/stars-end/prime-radiant-ai/actions/runs/" + (.databaseId | tostring))}]' \
    2>>"$LOG_FILE" || echo "[]"
}

# Query GitHub workflow health
query_github_health() {
  log "Querying GitHub workflow health..."

  if ! command -v gh >/dev/null 2>&1; then
    echo "[]"
    return 0
  fi

  gh run list --repo "$GH_REPO" \
    --json conclusion,workflowName \
    --limit 20 \
    --jq '[group_by(.workflowName) | .[] | {workflow: .[0].workflowName, total: length, failed: map(select(.conclusion != "success")) | length}] | sort_by(.failed) | reverse' \
    2>>"$LOG_FILE" || echo "[]"
}

# Main execution
main() {
  log "Starting founder daily data gathering..."

  if ! check_dependencies; then
    pipeline_fail "dependency_missing"
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  # Source resolution is now taxonomy-aware and memoized.
  if ! query_source; then
    require_active_dolt_source || true
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  if ! require_active_dolt_source; then
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  # Gather all data
  P0_ISSUES_JSON=$(query_p0_issues)
  if [[ -z "$P0_ISSUES_JSON" ]]; then P0_ISSUES_JSON="[]"; fi
  if ! jq -e 'type == "array"' <<<"${P0_ISSUES_JSON}" >/dev/null 2>&1; then
    pipeline_fail "beads_query_failed" "p0 issues query returned non-array JSON"
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  P1_ISSUES_JSON=$(query_p1_issues)
  if [[ -z "$P1_ISSUES_JSON" ]]; then P1_ISSUES_JSON="[]"; fi
  if ! jq -e 'type == "array"' <<<"${P1_ISSUES_JSON}" >/dev/null 2>&1; then
    pipeline_fail "beads_query_failed" "p1 issues query returned non-array JSON"
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  BLOCKING_ISSUES_JSON=$(query_blocking_issues)
  if [[ -z "$BLOCKING_ISSUES_JSON" ]]; then BLOCKING_ISSUES_JSON="[]"; fi
  if ! jq -e 'type == "array"' <<<"${BLOCKING_ISSUES_JSON}" >/dev/null 2>&1; then
    pipeline_fail "beads_query_failed" "blocking issues query returned non-array JSON"
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  STALE_ISSUES_JSON=$(query_stale_issues)
  if [[ -z "$STALE_ISSUES_JSON" ]]; then STALE_ISSUES_JSON="[]"; fi
  if ! jq -e 'type == "array"' <<<"${STALE_ISSUES_JSON}" >/dev/null 2>&1; then
    pipeline_fail "beads_query_failed" "stale issues query returned non-array JSON"
    build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"
    cat "$OUTPUT_FILE"
    return 1
  fi

  local alerts_json
  alerts_json=$(get_robot_alerts)

  DRIFT_STATUS=$(check_drift)

  FAILED_RUNS_JSON=$(query_github_failed)
  FAILED_COUNT=$(echo "$FAILED_RUNS_JSON" | jq 'length // 0')

  WORKFLOW_HEALTH_JSON=$(query_github_health)

  CRITICAL_COUNT=$(echo "$alerts_json" | jq -r '.summary.critical // 0' 2>/dev/null || echo "0")
  
  # Hygiene Metrics
  local stale_prs
  stale_prs=$(query_stale_prs)
  STALE_PRS_COUNT=$(echo "$stale_prs" | jq 'length // 0')
  
  BACKLOG_COUNT=$(query_backlog_count)
  
  local rescue_prs
  rescue_prs=$(query_rescue_prs)
  RESCUE_COUNT=$(echo "$rescue_prs" | jq 'length // 0')

  local alerts_array
  alerts_array=$(echo "$alerts_json" | jq -c '.alerts[:5] // []' 2>/dev/null || echo "[]")

  ALERTS_JSON=$alerts_array
  
  # Ensure numeric values have valid defaults
  CRITICAL_COUNT=${CRITICAL_COUNT:-0}
  FAILED_COUNT=${FAILED_COUNT:-0}
  STALE_PRS_COUNT=${STALE_PRS_COUNT:-0}
  BACKLOG_COUNT=${BACKLOG_COUNT:-0}
  RESCUE_COUNT=${RESCUE_COUNT:-0}
  
  build_pipeline_payload "$PIPELINE_STATUS" "$PIPELINE_REASON" "$PIPELINE_SOURCE" "$PIPELINE_ERROR"

  success "Data gathering complete"
  log "Output: $OUTPUT_FILE"

  cat "$OUTPUT_FILE"
}

# Format data as Slack message (≤300 chars main, details in thread)
format_slack_message() {
  local json_file="$1"
  
  if [ ! -f "$json_file" ]; then
    error "JSON file not found: $json_file"
    return 1
  fi
  
  local p0_count p1_count failed_count critical_count drift_status
  p0_count=$(jq '.beads.p0_issues | length' "$json_file")
  p1_count=$(jq '.beads.p1_issues | length' "$json_file")
  failed_count=$(jq '.github.failed_count' "$json_file")
  critical_count=$(jq '.beads.robot_alerts.critical' "$json_file")
  drift_status=$(jq -r '.beads.drift_status' "$json_file")
  local founder_status founder_reason founder_source
  founder_status=$(jq -r '.founder_pipeline.status // "unknown"' "$json_file")
  founder_source=$(jq -r '.founder_pipeline.source // "unknown"' "$json_file")
  founder_reason=$(jq -r '.founder_pipeline.reason // "unknown"' "$json_file")
  
  local stale_prs_count backlog_count rescue_count
  stale_prs_count=$(jq '.github.stale_prs_count' "$json_file")
  backlog_count=$(jq '.beads.backlog_count' "$json_file")
  rescue_count=$(jq '.github.rescue_count' "$json_file")
  
  # Determine overall status
  local status_emoji="✅"
  local status_text="All clear"
  
  if [ "$founder_status" != "ok" ]; then
    status_emoji="🚨"
    status_text="Action needed"
  elif [ "$drift_status" = "critical" ] || [ "$failed_count" -gt 0 ] || [ "$p0_count" -gt 5 ] || [ "$rescue_count" -gt 0 ]; then
    status_emoji="🚨"
    status_text="Action needed"
  elif [ "$drift_status" = "warning" ] || [ "$critical_count" -gt 50 ] || [ "$stale_prs_count" -gt 5 ] || [ "$backlog_count" -gt 20 ]; then
    status_emoji="⚠️"
    status_text="Review needed"
  fi
  
  # Build main message (≤300 chars)
  local today
  today=$(date +%Y-%m-%d)
  
  local main_msg="${status_emoji} *DX Daily* (${today}): ${status_text}
• P0: ${p0_count} | P1: ${p1_count} | GH fails: ${failed_count} | Rescue: ${rescue_count}
• Stale PRs: ${stale_prs_count} | Backlog: ${backlog_count} | Drift: ${drift_status}
• Founder source: ${founder_source} (${founder_reason})"
  
  echo "$main_msg"
  
  # If issues exist, output details for thread
  if [ "$status_text" != "All clear" ]; then
    echo "---THREAD---"
    
    if [ "$rescue_count" -gt 0 ]; then
        echo "*Rescue Branches (Canonical Violations):*"
        jq -r '.beads.p0_issues[:3] | .[] | "• \(.id): \(.title | .[0:60])"' "$json_file" 2>/dev/null || true
    fi

    if [ "$p0_count" -gt 0 ]; then
        echo "*Top P0 issues:*"
        jq -r '.beads.p0_issues[:3] | .[] | "• \(.id): \(.title | .[0:60])"' "$json_file" 2>/dev/null || true
    fi
    
    if [ "$founder_status" != "ok" ]; then
      echo ""
      echo "*Founder Pipeline:*"
      echo "• status=${founder_status} reason=${founder_reason} source=${founder_source}"
    fi

    if [ "$failed_count" -gt 0 ]; then
      echo ""
      echo "*Failed GitHub Actions:*"
      jq -r '.github.failed_runs[:3] | .[] | "• \(.workflow): \(.url)"' "$json_file" 2>/dev/null || true
    fi
  fi
}

# Run with options
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --json         Output raw JSON (default)"
  echo "  --slack        Output formatted Slack message"
  echo "  --help         Show this help"
}

main_with_options() {
  local output_mode="json"
  
  while [ $# -gt 0 ]; do
    case "$1" in
      --slack) output_mode="slack"; shift ;;
      --json) output_mode="json"; shift ;;
      --help) usage; exit 0 ;;
      *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
  
  # Create temp file to capture JSON
  local temp_json
  temp_json=$(mktemp)
  
  # Run main and capture JSON (stdout only), let stderr pass through for logs
  main > "$temp_json"
  local exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    cat "$temp_json"
    rm -f "$temp_json"
    return $exit_code
  fi
  
  if [ "$output_mode" = "slack" ]; then
    format_slack_message "$temp_json"
  else
    cat "$temp_json"
  fi
  
  rm -f "$temp_json"
}

# Run with options
main_with_options "$@"
