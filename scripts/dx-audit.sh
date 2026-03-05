#!/usr/bin/env bash
#
# dx-audit.sh
#
# Fleet audit command for daily and weekly checks.
# Produces a machine-readable contract for downstream automation.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
STATE_ROOT_LEGACY1="${HOME}/.dx-state/fleet-sync"
STATE_ROOT_LEGACY2="${HOME}/.dx-state/fleet_sync"

MODE="weekly"
OUTPUT_SLACK=0
STATE_ONLY=0

if [[ -f "${SCRIPT_DIR}/canonical-targets.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/canonical-targets.sh"
fi

if ! declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1 || [[ "${#CANONICAL_REQUIRED_REPOS[@]}" -eq 0 ]]; then
  CANONICAL_REQUIRED_REPOS=(agent-skills prime-radiant-ai affordabot llm-common)
fi
if ! declare -p CANONICAL_IDES >/dev/null 2>&1 || [[ "${#CANONICAL_IDES[@]}" -eq 0 ]]; then
  CANONICAL_IDES=(antigravity claude-code codex-cli opencode gemini-cli)
fi

DAILY_CHECK_IDS_DEFAULT=(
  beads_dolt
  tool_mcp_health
  required_service_health
  op_auth_readiness
  alerts_transport_readiness
)

WEEKLY_CHECK_IDS_DEFAULT=(
  canonical_repo_hygiene
  skills_symlink_integrity
  global_constraints_rails
  ide_config_presence_and_drift
  cron_health
  service_cap_and_forbidden_components
  trailer_compliance
  deployment_stack_readiness
  railway_auth_context
  gh_deploy_readiness
)

DAILY_CHECK_IDS=()
WEEKLY_CHECK_IDS=()
SLACK_CHANNEL="#dx-alerts"
AUDIT_COORDINATOR_HOST=""
SLACK_POST_ON_GREEN=true
SLACK_THREAD_MODE=false
TOOL_HEALTH_JSON=""
TOOL_HEALTH_LINES=""
AUDIT_DAILY_LATEST=""
AUDIT_DAILY_HISTORY=""
AUDIT_WEEKLY_LATEST=""
AUDIT_WEEKLY_HISTORY=""
GEMINI_GRACE_DAYS=7
GEMINI_ENFORCE_AFTER=7

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

write_atomic() {
  local target="$1"
  local data="$2"
  local tmp
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  printf '%s\n' "$data" > "$tmp"
  mv "$tmp" "$target"
}

manifest_list() {
  local list_name="$1"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    return
  fi
  awk -v section="  ${list_name}:" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/,"", s); return s }
    $0 ~ /^audit:/ { in_audit=1; next }
    in_audit && /^[^[:space:]]/ { in_audit=0 }
    in_audit && $0 ~ "^" section "$" { in_list=1; next }
    in_audit && in_list {
      if ($0 ~ /^[^[:space:]]/) {
        in_list=0
        next
      }
      if ($0 ~ /^[[:space:]]{2}[^[:space:]]+:[[:space:]]*$/) {
        in_list=0
        next
      }
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        s=$0
        sub(/^[[:space:]]*-[[:space:]]*/, "", s)
      sub(/[[:space:]]*#.*/, "", s)
      gsub(/^"|"$/, "", s)
      gsub(/^'\''|'\''$/, "", s)
      s=trim(s)
      if (s != "") print s
      }
      next
    }
  ' "$MANIFEST_PATH"
}

manifest_scalar() {
  local section="$1"
  local key="$2"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    return
  fi
  awk -v section="  ${section}:" -v key="    ${key}:" -v want="$section" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/,"", s); return s }
    $0 ~ /^audit:/ { in_audit=1; next }
    in_audit && /^[^[:space:]]/ { in_audit=0; in_section=0; in_key=0 }
    !in_audit { next }
    in_audit && $0 ~ "^" section "$" { in_section=1; in_key=0; next }
    in_audit && in_section && $0 !~ /^  / { in_section=0; in_key=0; next }
    in_audit && in_section && $0 ~ "^" key { in_key=1; next }
    in_audit && in_section && in_key {
      value=$0
      sub(/^[[:space:]]+[^:]+:[[:space:]]*/, "", value)
      gsub(/#.*/, "", value)
      gsub(/^"|"$/, "", value)
      gsub(/^'\''|'\''$/, "", value)
      value=trim(value)
      print value
      exit
    }
  ' "$MANIFEST_PATH"
}

manifest_scalar_top() {
  local key="$1"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    return
  fi
  awk -v raw_key="$key" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/,"", s); return s }
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
    if (line ~ ("^" raw_key ":")) {
        value=$0
        sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", value)
        gsub(/#.*/, "", value)
        gsub(/^"|"$/, "", value)
        gsub(/^'\''|'\''$/, "", value)
        value=trim(value)
        print value
        exit
      }
    }
  ' "$MANIFEST_PATH"
}

manifest_scalar_audit() {
  local section="$1"
  local key="$2"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    return
  fi
  awk -v section="  ${section}:" -v key="    ${key}:" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/,"", s); return s }
    $0 ~ /^audit:/ { in_audit=1; next }
    in_audit && /^[^[:space:]]/ { in_audit=0; in_section=0; in_key=0 }
    !in_audit { next }
    in_audit && $0 ~ "^" section "$" { in_section=1; in_key=0; next }
    in_audit && in_section && $0 !~ /^  / { in_section=0; in_key=0; next }
    in_audit && in_section && $0 ~ "^" key {
      value=$0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/#.*/, "", value)
      gsub(/^"|"$/, "", value)
      gsub(/^'\''|'\''$/, "", value)
      value=trim(value)
      print value
      exit
    }
  ' "$MANIFEST_PATH"
}

expand_path_like() {
  local value="$1"
  if [[ "$value" == "~/"* ]]; then
    printf '%s\n' "${value/#~\//$HOME/}"
    return
  fi
  printf '%s\n' "$value"
}

load_manifest_config() {
  local -a daily_from_manifest=()
  local -a weekly_from_manifest=()
  local -a legacy_roots=()

  local line
  while IFS= read -r line; do
    daily_from_manifest+=("$line")
  done < <(manifest_list "daily_checks")
  while IFS= read -r line; do
    weekly_from_manifest+=("$line")
  done < <(manifest_list "weekly_checks")
  if [[ "${#daily_from_manifest[@]}" -gt 0 ]]; then
    DAILY_CHECK_IDS=("${daily_from_manifest[@]}")
  else
    DAILY_CHECK_IDS=("${DAILY_CHECK_IDS_DEFAULT[@]}")
  fi
  if [[ "${#weekly_from_manifest[@]}" -gt 0 ]]; then
    WEEKLY_CHECK_IDS=("${weekly_from_manifest[@]}")
  else
    WEEKLY_CHECK_IDS=("${WEEKLY_CHECK_IDS_DEFAULT[@]}")
  fi

  local coord=""
  coord="$(manifest_scalar_top "coordinator_host" 2>/dev/null || true)"
  if [[ -n "$coord" ]]; then
    AUDIT_COORDINATOR_HOST="$coord"
  fi

  local pgl="$(manifest_scalar_audit "slack" "channel" 2>/dev/null || true)"
  [[ -n "$pgl" ]] && SLACK_CHANNEL="$pgl"
  local post_on_green_value
  post_on_green_value="$(manifest_scalar_audit "slack" "post_on_green" 2>/dev/null || true)"
  local thread_mode_value
  thread_mode_value="$(manifest_scalar_audit "slack" "thread_mode" 2>/dev/null || true)"
  if [[ "${post_on_green_value:-}" == "false" ]]; then
    SLACK_POST_ON_GREEN=false
  fi
  if [[ "${thread_mode_value:-}" == "true" ]]; then
    SLACK_THREAD_MODE=true
  fi

  local grace_value
  local enforce_value
  grace_value="$(manifest_scalar_audit "gemini_enforcement" "grace_days" 2>/dev/null || true)"
  enforce_value="$(manifest_scalar_audit "gemini_enforcement" "enforce_after" 2>/dev/null || true)"
  [[ -n "$grace_value" && "$grace_value" =~ ^[0-9]+$ ]] && GEMINI_GRACE_DAYS="$grace_value"
  [[ -n "$enforce_value" && "$enforce_value" =~ ^[0-9]+$ ]] && GEMINI_ENFORCE_AFTER="$enforce_value"
  if [[ "$GEMINI_ENFORCE_AFTER" -lt "$GEMINI_GRACE_DAYS" ]]; then
    GEMINI_ENFORCE_AFTER="$GEMINI_GRACE_DAYS"
  fi

  local threshold_tool_stale_hours=""
  local threshold_dolt_stale_minutes=""
  local threshold_unknown_host_escalation_runs=""
  threshold_tool_stale_hours="$(manifest_scalar_audit "thresholds" "tool_stale_hours" 2>/dev/null || true)"
  threshold_dolt_stale_minutes="$(manifest_scalar_audit "thresholds" "dolt_stale_minutes" 2>/dev/null || true)"
  threshold_unknown_host_escalation_runs="$(manifest_scalar_audit "thresholds" "unknown_host_escalation_runs" 2>/dev/null || true)"
  if [[ -n "$threshold_tool_stale_hours" && "$threshold_tool_stale_hours" =~ ^[0-9]+$ ]]; then
    TOOL_STALE_HOURS="$threshold_tool_stale_hours"
  fi
  if [[ -n "$threshold_dolt_stale_minutes" && "$threshold_dolt_stale_minutes" =~ ^[0-9]+$ ]]; then
    DOLT_STALE_MINUTES="$threshold_dolt_stale_minutes"
  fi
  if [[ -n "$threshold_unknown_host_escalation_runs" && "$threshold_unknown_host_escalation_runs" =~ ^[0-9]+$ ]]; then
    UNKNOWN_HOST_ESCALATION_RUNS="$threshold_unknown_host_escalation_runs"
  fi

  local layout_tool_health_json=""
  local layout_tool_health_lines=""
  local layout_daily_latest=""
  local layout_daily_history=""
  local layout_weekly_latest=""
  local layout_weekly_history=""
  layout_tool_health_json="$(manifest_scalar_top "tool_health_json" 2>/dev/null || true)"
  layout_tool_health_lines="$(manifest_scalar_top "tool_health_lines" 2>/dev/null || true)"
  layout_daily_latest="$(manifest_scalar_top "daily_audit_latest" 2>/dev/null || true)"
  layout_daily_history="$(manifest_scalar_top "daily_audit_history" 2>/dev/null || true)"
  layout_weekly_latest="$(manifest_scalar_top "weekly_audit_latest" 2>/dev/null || true)"
  layout_weekly_history="$(manifest_scalar_top "weekly_audit_history" 2>/dev/null || true)"

  TOOL_HEALTH_JSON="${STATE_ROOT}/${layout_tool_health_json:-tool-health.json}"
  TOOL_HEALTH_LINES="${STATE_ROOT}/${layout_tool_health_lines:-tool-health.lines}"
  AUDIT_DAILY_LATEST="${STATE_ROOT}/${layout_daily_latest:-audit/daily/latest.json}"
  AUDIT_DAILY_HISTORY="${STATE_ROOT}/${layout_daily_history:-audit/daily/history}"
  AUDIT_WEEKLY_LATEST="${STATE_ROOT}/${layout_weekly_latest:-audit/weekly/latest.json}"
  AUDIT_WEEKLY_HISTORY="${STATE_ROOT}/${layout_weekly_history:-audit/weekly/history}"

  while IFS= read -r line; do
    legacy_roots+=("$line")
  done < <(awk -v active="  - " '
    BEGIN { in_legacy=0 }
    $0 ~ /^legacy_state_roots:/ { in_legacy=1; next }
    in_legacy {
      if ($0 ~ /^[^[:space:]]/) { in_legacy=0 }
      else if ($0 ~ "^[[:space:]]*- ") {
        s=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", s); gsub(/#.*/, "", s); gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); if (s!="") print s
      }
    }
  ' "$MANIFEST_PATH")
  if [[ "${#legacy_roots[@]}" -gt 0 ]]; then
    STATE_ROOT_LEGACY1="$(expand_path_like "${legacy_roots[0]:-"${STATE_ROOT_LEGACY1}"}")"
    STATE_ROOT_LEGACY2="$(expand_path_like "${legacy_roots[1]:-"${STATE_ROOT_LEGACY2}"}")"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --daily)
        MODE="daily"
        shift
        ;;
      --weekly)
        MODE="weekly"
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        shift 2
        ;;
      --json|--json-only)
        shift
        ;;
      --state-only)
        STATE_ONLY=1
        shift
        ;;
      --slack)
        OUTPUT_SLACK=1
        shift
        ;;
      --help|-h)
        cat <<'EOF'
Usage:
  dx-audit.sh --daily [--state-dir PATH]
  dx-audit.sh --weekly [--state-dir PATH]
  dx-audit.sh --slack (prints deterministic slack message)
EOF
        exit 0
        ;;
      *)
        echo "Unknown arg: $1" >&2
        exit 1
        ;;
    esac
  done
}

append_reason() {
  local code="$1"
  [[ -z "$code" ]] && return
  for existing in "${reason_codes[@]-}"; do
    [[ "$existing" == "$code" ]] && return
  done
  reason_codes+=("$code")
}

is_member() {
  local target="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$target" ]] && return 0
  done
  return 1
}

host_index_for_name() {
  local target="$1"
  local idx
  for idx in "${!host_order[@]}"; do
    if [[ "${host_order[$idx]}" == "$target" ]]; then
      printf '%s' "$idx"
      return 0
    fi
  done
  return 1
}

normalized_status_count() {
  local status="$1"
  case "$status" in
    pass|green)
      echo pass
      ;;
    warn|yellow)
      echo warn
      ;;
    fail|red)
      echo fail
      ;;
    *)
      echo unknown
      ;;
  esac
}

append_check() {
  local check_id="$1"
  local host="$2"
  local status="$3"
  local severity="$4"
  local details="$5"
  local next_action="${6:-}"

  [[ -z "$check_id" ]] && return
  [[ -z "$host" ]] && host="local"
  check_id="${check_id#fleet.v2.2.}"
  check_id="fleet.v2.2.${check_id}"

  local row
  if [[ -n "$next_action" ]]; then
    row="{\"id\":\"$check_id\",\"host\":\"$(json_escape "$host")\",\"status\":\"$status\",\"severity\":\"$(json_escape "$severity")\",\"details\":\"$(json_escape "$details")\",\"next_action\":\"$(json_escape "$next_action")\"}"
  else
    row="{\"id\":\"$check_id\",\"host\":\"$(json_escape "$host")\",\"status\":\"$status\",\"severity\":\"$(json_escape "$severity")\",\"details\":\"$(json_escape "$details")\"}"
  fi
  checks+=("$row")

  local host_idx
  if host_idx="$(host_index_for_name "$host")"; then
    :
  else
    host_idx=${#host_order[@]}
    host_order+=("$host")
    host_overall+=("green")
    host_checks+=("")
  fi
  if [[ -n "${host_checks[$host_idx]:-}" ]]; then
    host_checks[$host_idx]+=",${row}"
  else
    host_checks[$host_idx]="$row"
  fi

  case "$status" in
    pass)
      pass_count=$((pass_count + 1))
      if [[ "$status" == "pass" ]]; then
        :
      fi
      ;;
    warn)
      warn_count=$((warn_count + 1))
      if [[ "${host_overall[$host_idx]}" == "green" ]]; then
        host_overall[$host_idx]="yellow"
      fi
      ;;
    fail)
      fail_count=$((fail_count + 1))
      host_overall[$host_idx]="red"
      ;;
    unknown)
      unknown_count=$((unknown_count + 1))
      if [[ "${host_overall[$host_idx]}" == "green" ]]; then
        host_overall[$host_idx]="yellow"
      fi
      ;;
  esac
}

append_weekly_check() {
  local check_id="$1"
  local host="$2"
  local status="$3"
  local severity="$4"
  local details="$5"
  append_check "$check_id" "$host" "$status" "$severity" "$details"
}

weekly_check_canonical_repo_hygiene() {
  local local_host="local"
  local missing=0
  local repo
  for repo in "${CANONICAL_REQUIRED_REPOS[@]}"; do
    local repo_path="${HOME}/${repo}"
    if [[ ! -d "$repo_path/.git" ]]; then
      missing=$((missing + 1))
      continue
    fi
    if ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      missing=$((missing + 1))
      continue
    fi
  done
  if [[ "$missing" -gt 0 ]]; then
    append_weekly_check "canonical_repo_hygiene" "$local_host" "warn" "medium" "$missing required canonical repos missing"
  else
    append_weekly_check "canonical_repo_hygiene" "$local_host" "pass" "low" "All required canonical repos present"
  fi
}

weekly_check_skills_symlink() {
  local local_host="local"
  local target="${HOME}/.agent/skills"
  if [[ -L "$target" ]] || [[ -d "$target" ]]; then
    if [[ -L "$target" ]] && [[ "$(readlink "$target")" == *"agent-skills"* ]]; then
      append_weekly_check "skills_symlink_integrity" "$local_host" "pass" "low" "~/.agent/skills points to canonical path"
      return
    fi
    if [[ -d "$target" ]] && [[ "$target" == "$HOME/agent-skills" ]]; then
      append_weekly_check "skills_symlink_integrity" "$local_host" "pass" "low" "~/.agent/skills is canonical directory"
      return
    fi
    append_weekly_check "skills_symlink_integrity" "$local_host" "warn" "medium" "~/.agent/skills exists but not canonical"
    return
  fi
  append_weekly_check "skills_symlink_integrity" "$local_host" "warn" "medium" "~/.agent/skills missing"
}

weekly_check_global_constraints() {
  local local_host="local"
  local constraint_file="${SCRIPT_DIR}/../dist/dx-global-constraints.md"
  if [[ -f "$constraint_file" ]]; then
    append_weekly_check "global_constraints_rails" "$local_host" "pass" "low" "Global constraints present"
  else
    append_weekly_check "global_constraints_rails" "$local_host" "warn" "low" "Global constraints file missing"
  fi
}

gemini_artifacts_present() {
  local missing=0
  local candidate
  for candidate in \
    "${HOME}/.gemini/GEMINI.md" \
    "${HOME}/.gemini/antigravity/mcp_config.json"; do
    if [[ ! -f "$candidate" ]]; then
      missing=1
      break
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    return 1
  fi

  if [[ -x "${HOME}/.gemini/gemini" ]] || [[ -x "${HOME}/.gemini/gemini-cli" ]] || command -v gemini >/dev/null 2>&1 || command -v gemini-cli >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

gemini_enforcement_state() {
  if gemini_artifacts_present; then
    local marker="${STATE_ROOT}/enforcement/gemini-enforcement.json"
    [[ -f "$marker" ]] && rm -f "$marker"
    echo "pass"
    return
  fi

  local marker="${STATE_ROOT}/enforcement/gemini-enforcement.json"
  local now_epoch
  local first_epoch
  now_epoch="$(date -u +%s)"
  mkdir -p "$(dirname "$marker")"
  first_epoch="$(sed -n '1p' "$marker" 2>/dev/null || printf '')"
  if [[ -z "$first_epoch" || ! "$first_epoch" =~ ^[0-9]+$ ]]; then
    first_epoch="$now_epoch"
    printf '%s\n' "$first_epoch" > "$marker"
  fi

  local days_missing
  days_missing=$(( (now_epoch - first_epoch) / 86400 ))
  if [[ "$days_missing" -le "$GEMINI_GRACE_DAYS" ]]; then
    echo "warn"
  elif [[ "$days_missing" -gt "$GEMINI_ENFORCE_AFTER" ]]; then
    echo "fail"
  else
    echo "warn"
  fi
}

weekly_check_ide_config() {
  local local_host="local"
  local missing=0
  local file
  for file in "${HOME}/.claude/settings.json" "${HOME}/.claude.json" "${HOME}/.codex/config.toml" "${HOME}/.opencode/config.json" "${HOME}/.gemini/antigravity/mcp_config.json"; do
    [[ -f "$file" ]] || missing=$((missing + 1))
  done
  if [[ "$missing" -gt 0 ]]; then
    append_weekly_check "ide_config_presence_and_drift" "$local_host" "fail" "high" "Missing canonical IDE config files required by governance checks"
    return
  fi

  local gemini_state
  gemini_state="$(gemini_enforcement_state)"
  if [[ "$gemini_state" == "fail" ]]; then
    append_weekly_check "ide_config_presence_and_drift" "$local_host" "fail" "high" "Gemini CLI lane outside enforcement window: missing ~/.gemini/GEMINI.md, ~/.gemini/antigravity/mcp_config.json, or gemini binary"
    return
  fi
  if [[ "$gemini_state" == "warn" ]]; then
    append_weekly_check "ide_config_presence_and_drift" "$local_host" "warn" "medium" "Gemini CLI lane missing required artifacts: grace window active"
    return
  fi

  append_weekly_check "ide_config_presence_and_drift" "$local_host" "pass" "low" "Canonical IDE config files present"
}

weekly_check_cron_health() {
  local local_host="local"
  if command -v crontab >/dev/null 2>&1; then
    if crontab -l >/dev/null 2>&1; then
      append_weekly_check "cron_health" "$local_host" "pass" "low" "crontab readable"
    else
      append_weekly_check "cron_health" "$local_host" "warn" "low" "crontab present but inaccessible"
    fi
  else
    append_weekly_check "cron_health" "$local_host" "warn" "low" "crontab command missing"
  fi
}

weekly_check_service_capabilities() {
  local local_host="local"
  local blocked=0
  local forbidden_files=("${HOME}/.agents/tools/prohibited" "${HOME}/.agent/prohibited")
  local ff
  for ff in "${forbidden_files[@]}"; do
    [[ -f "$ff" ]] && blocked=$((blocked + 1))
  done

  if [[ "$blocked" -gt 0 ]]; then
    append_weekly_check "service_cap_and_forbidden_components" "$local_host" "warn" "medium" "$blocked forbidden component markers detected"
  else
    append_weekly_check "service_cap_and_forbidden_components" "$local_host" "pass" "low" "No blocked legacy markers"
  fi
}

weekly_check_trailer_compliance() {
  local local_host="local"
  local msg
  msg="$(git -C "${HOME}/agent-skills" log -1 --pretty=%B 2>/dev/null || true)"
  if [[ "$msg" == *"Feature-Key:"* ]] && [[ "$msg" == *"Agent:"* ]]; then
    append_weekly_check "trailer_compliance" "$local_host" "pass" "low" "Latest commit has required trailers"
  else
    append_weekly_check "trailer_compliance" "$local_host" "warn" "medium" "Latest commit missing Feature-Key or Agent trailer"
  fi
}

weekly_check_deployment_stack() {
  local local_host="local"
  local has_railway=0
  local has_gh=0
  command -v dx-fleet-check >/dev/null 2>&1 && has_railway=$((has_railway + 1))
  command -v gh >/dev/null 2>&1 && has_gh=$((has_gh + 1))

  if [[ "$has_railway" -gt 0 ]] || [[ "$has_gh" -gt 0 ]]; then
    append_weekly_check "deployment_stack_readiness" "$local_host" "pass" "low" "Deployment tooling available"
  else
    append_weekly_check "deployment_stack_readiness" "$local_host" "warn" "low" "No deployment tooling detected"
  fi
}

weekly_check_railway_auth() {
  local local_host="local"
  if [[ -n "${RAILWAY_API_TOKEN:-}" ]] || [[ -n "${RAILWAY_PROJECT_ID:-}" ]] || [[ -n "${RAILWAY_SERVICE_ID:-}" ]]; then
    append_weekly_check "railway_auth_context" "$local_host" "pass" "low" "Railway auth context set"
  else
    append_weekly_check "railway_auth_context" "$local_host" "warn" "low" "RAILWAY_API_TOKEN / project context not set"
  fi
}

weekly_check_gh_readiness() {
  local local_host="local"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    append_weekly_check "gh_deploy_readiness" "$local_host" "pass" "low" "gh authenticated"
  else
    append_weekly_check "gh_deploy_readiness" "$local_host" "warn" "low" "gh missing or unauthenticated"
  fi
}

run_weekly_governance() {
  local check_id
  for check_id in "${WEEKLY_CHECK_IDS[@]}"; do
    case "$check_id" in
      canonical_repo_hygiene)
        weekly_check_canonical_repo_hygiene
        ;;
      skills_symlink_integrity)
        weekly_check_skills_symlink
        ;;
      global_constraints_rails)
        weekly_check_global_constraints
        ;;
      ide_config_presence_and_drift)
        weekly_check_ide_config
        ;;
      cron_health)
        weekly_check_cron_health
        ;;
      service_cap_and_forbidden_components)
        weekly_check_service_capabilities
        ;;
      trailer_compliance)
        weekly_check_trailer_compliance
        ;;
      deployment_stack_readiness)
        weekly_check_deployment_stack
        ;;
      railway_auth_context)
        weekly_check_railway_auth
        ;;
      gh_deploy_readiness)
        weekly_check_gh_readiness
        ;;
      *)
        append_weekly_check "$check_id" "local" "warn" "low" "Unknown weekly check id in manifest"
        ;;
    esac
  done
  append_reason "weekly_check_suite_complete"
}

daily_health_source() {
  local source="${TOOL_HEALTH_JSON:-${STATE_ROOT}/tool-health.json}"
  if [[ -f "$source" ]]; then
    echo "$source"
    return 0
  fi
  if [[ -f "${STATE_ROOT_LEGACY1}/tool-health.json" ]]; then
    append_reason "fallback_from_legacy_fleet_sync"
    echo "${STATE_ROOT_LEGACY1}/tool-health.json"
    return 0
  fi
  if [[ -f "${STATE_ROOT_LEGACY2}/tool-health.json" ]]; then
    append_reason "fallback_from_legacy_fleet_sync_alt"
    echo "${STATE_ROOT_LEGACY2}/tool-health.json"
    return 0
  fi
  return 1
}

load_daily_checks_from_fleet_check_payload() {
  local payload="$1"
  local had_rows=0
  local host
  local check_id
  local status
  local severity
  local details
  local normalized
  local key
  local -a observed_pairs=()
  local -a observed_host_order_local=()

  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  while IFS=$'\t' read -r host check_id status severity details; do
    [[ -z "$check_id" ]] && continue
    if ! is_member "$check_id" "${DAILY_CHECK_IDS[@]}"; then
      continue
    fi
    had_rows=1
    host="${host:-local}"
    if ! is_member "$host" "${observed_host_order_local[@]}"; then
      observed_host_order_local+=("$host")
    fi
    normalized="$(normalized_status_count "$status")"
    key="${host}:${check_id}"
    if ! is_member "$key" "${observed_pairs[@]}"; then
      observed_pairs+=("$key")
    fi
    append_check "$check_id" "$host" "$normalized" "$severity" "$details"
  done < <(printf '%s' "$payload" | jq -r '.hosts[]? | .host as $host | .checks[]? | "\($host // "local")\t\(.id // "")\t\(.status // "unknown")\t\(.severity // "low")\t\((.details // "") | gsub("\t"; " ") | gsub("\n"; " ") )"')

  if [[ "$had_rows" -eq 0 ]]; then
    return 1
  fi

  local h
  for h in "${observed_host_order_local[@]}"; do
    for check_id in "${DAILY_CHECK_IDS[@]}"; do
      key="${h}:${check_id}"
      if ! is_member "$key" "${observed_pairs[@]}"; then
        append_reason "missing_expected_daily_check_${check_id}"
        append_check "$check_id" "$h" "warn" "low" "Expected daily check missing from Fleet Sync check output"
        observed_pairs+=("$key")
      fi
    done
  done
  return 0
}

parse_daily_checks_with_jq() {
  local source_file="$1"
  jq -r '.hosts[]? as $h | $h.host as $host | ($h.checks // [])[]? | "\($host // "local")\t\(.id // "")\t\(.status // "unknown")\t\(.severity // "low")\t\(.details // "")"' "$source_file"
}

parse_daily_checks_fallback() {
  local source_file="$1"
  python3 - "$source_file" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8", errors="ignore") as fp:
    data = json.load(fp)
for host_obj in data.get("hosts", []):
    host = host_obj.get("host", "local")
    for c in host_obj.get("checks", []):
        print(
            "\t".join(
                [
                    host,
                    c.get("id", ""),
                    c.get("status", "unknown"),
                    c.get("severity", "low"),
                    c.get("details", ""),
                ]
            )
        )
PY
}

load_daily_checks() {
  local source_file=""
  local had_rows=0
  local host
  local check_id
  local status
  local severity
  local details
  local normalized
  local key
  local -a observed_pairs=()
  declare -a observed_host_order=()

  if ! source_file="$(daily_health_source)"; then
    append_reason "missing_daily_state"
    for check_id in "${DAILY_CHECK_IDS[@]}"; do
      append_check "$check_id" "local" "warn" "low" "No Fleet Sync state snapshot found at ${STATE_ROOT}/tool-health.json"
    done
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r host check_id status severity details; do
      [[ -z "$check_id" ]] && continue
      if ! is_member "$check_id" "${DAILY_CHECK_IDS[@]}"; then
        continue
      fi
      had_rows=1
      host="${host:-local}"
      if ! is_member "$host" "${observed_host_order[@]}"; then
        observed_host_order+=("$host")
      fi
      normalized="$(normalized_status_count "$status")"
      key="${host}:${check_id}"
      if ! is_member "$key" "${observed_pairs[@]}"; then
        observed_pairs+=("$key")
      fi
      append_check "$check_id" "$host" "$normalized" "$severity" "$details"
    done < <(parse_daily_checks_with_jq "$source_file")
  elif command -v python3 >/dev/null 2>&1; then
    while IFS=$'\t' read -r host check_id status severity details; do
      [[ -z "$check_id" ]] && continue
      if ! is_member "$check_id" "${DAILY_CHECK_IDS[@]}"; then
        continue
      fi
      had_rows=1
      host="${host:-local}"
      if ! is_member "$host" "${observed_host_order[@]}"; then
        observed_host_order+=("$host")
      fi
      normalized="$(normalized_status_count "$status")"
      key="${host}:${check_id}"
      if ! is_member "$key" "${observed_pairs[@]}"; then
        observed_pairs+=("$key")
      fi
      append_check "$check_id" "$host" "$normalized" "$severity" "$details"
    done < <(parse_daily_checks_fallback "$source_file")
  else
    append_reason "missing_payload_parser"
    for check_id in "${DAILY_CHECK_IDS[@]}"; do
      append_check "$check_id" "local" "warn" "low" "Missing jq and python3, unable to parse Fleet Sync state snapshot"
    done
    return 1
  fi

  if [[ "$had_rows" -eq 0 ]]; then
    append_reason "empty_daily_state"
    observed_host_order=(local)
    for host in local; do
    for check_id in "${DAILY_CHECK_IDS[@]}"; do
      key="${host}:${check_id}"
      if ! is_member "$key" "${observed_pairs[@]}"; then
        append_check "$check_id" "$host" "warn" "low" "Fleet Sync state payload had no checks"
        observed_pairs+=("$key")
      fi
    done
  done
    return 0
  fi

  local h
  for h in "${observed_host_order[@]}"; do
    for check_id in "${DAILY_CHECK_IDS[@]}"; do
      key="${h}:${check_id}"
      if ! is_member "$key" "${observed_pairs[@]}"; then
        append_reason "missing_expected_daily_check_${check_id}"
        append_check "$check_id" "$h" "warn" "low" "Expected daily check missing from state snapshot"
        observed_pairs+=("$key")
      fi
    done
  done
  return 0
}

gather_checks() {
  case "$MODE" in
    daily)
      if ! load_daily_checks; then
        :
      fi
      append_reason "daily_check_suite_complete"
      ;;
    weekly)
      run_weekly_governance
      append_reason "weekly_check_suite_complete"
      ;;
    *)
      echo "Unknown mode: $MODE" >&2
      exit 2
      ;;
  esac
}

build_hosts_payload() {
  local host_json="["
  local first_host=1
  local host_idx
  local host
  local checks_for_host
  for host_idx in "${!host_order[@]}"; do
    host="${host_order[$host_idx]}"
    checks_for_host="${host_checks[$host_idx]:-}"
    if [[ "$first_host" -eq 1 ]]; then
      first_host=0
    else
      host_json+=","
    fi
    host_json+="{\"host\":\"$(json_escape "$host")\",\"overall\":\"${host_overall[$host_idx]}\",\"checks\":[$checks_for_host]}"
  done
  host_json+="]"
  printf '%s' "$host_json"
}

build_repair_hints() {
  local -a rows=()
  local pair
  local -a seen_pairs=()
  local row
  for row in "${checks[@]}"; do
    [[ "$row" != *"\"status\":\"fail\""* && "$row" != *"\"status\":\"warn\""* ]] && continue
    local host
    local rid
    host="$(printf '%s' "$row" | sed -n 's/.*"host":"\([^"]*\)".*/\1/p')"
    rid="$(printf '%s' "$row" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
    if [[ -z "$rid" ]]; then
      continue
    fi
    pair="${host}|${rid}"
    if is_member "$pair" "${seen_pairs[@]}"; then
      continue
    fi
    seen_pairs+=("$pair")
    rows+=("{\"host\":\"$(json_escape "$host")\",\"check_id\":\"$(json_escape "$rid")\",\"command\":\"dx-fleet repair --json\"}")
  done
  local json="["
  local first=1
  for row in "${rows[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      json+="$row"
      first=0
    else
      json+=",$row"
    fi
  done
  json+="]"
  printf '%s' "$json"
}

build_reason_codes_json() {
  local out="["
  local first=1
  local row
  for row in "${reason_codes[@]-}"; do
    if [[ "$first" -eq 1 ]]; then
      out+="\"$row\""
      first=0
    else
      out+=",\"$row\""
    fi
  done
  out+="]"
  printf '%s' "$out"
}

render_slack_text() {
  local fleet_status="$1"
  local hosts_failed="$2"
  local summary_green summary_yellow summary_red summary_unknown
  summary_green="$pass_count"
  summary_yellow="$warn_count"
  summary_red="$fail_count"
  summary_unknown="$unknown_count"

  local line
  line="🛰️ dx-audit ${MODE}: ${fleet_status}. checks pass=$summary_green warn=$summary_yellow fail=$summary_red unknown=$summary_unknown hosts_failed=$hosts_failed."
  if [[ "$fleet_status" == "green" ]]; then
    if [[ "$SLACK_POST_ON_GREEN" == "true" ]]; then
      line+=" ✅ no action needed"
    else
      line+=" no action needed"
    fi
  elif [[ "$fleet_status" == "yellow" ]]; then
    line+=" ⚠️ run: dx-fleet repair --json"
  else
    line+=" ❗ remediation required: dx-fleet repair --json"
  fi
  printf '%s' "$line"
}

render_payload() {
  local summary_hosts_checked=${#host_order[@]}
  local hosts_failed=0
  local host_idx
  local overall
  local host
  for host_idx in "${!host_order[@]}"; do
    host="${host_order[$host_idx]}"
    overall="${host_overall[$host_idx]:-green}"
    [[ "$overall" == "red" ]] && hosts_failed=$((hosts_failed + 1))
  done

  local fleet_status="green"
  if [[ "$fail_count" -gt 0 ]]; then
    fleet_status="red"
  elif [[ "$warn_count" -gt 0 ]]; then
    fleet_status="yellow"
  elif [[ "$unknown_count" -gt 0 ]]; then
    fleet_status="unknown"
  fi

  local checks_json="["
  local first=1
  local row
  for row in "${checks[@]}"; do
    if [[ "$first" -eq 1 ]]; then
      checks_json+="$row"
      first=0
    else
      checks_json+=",$row"
    fi
  done
  checks_json+="]"

  local host_payload
  host_payload="$(build_hosts_payload)"
  local repair_hints_json
  repair_hints_json="$(build_repair_hints)"
  local reasons_json
  reasons_json="$(build_reason_codes_json)"
  local state_latest="$AUDIT_DAILY_LATEST"
  local state_history="$AUDIT_DAILY_HISTORY"
  local state_file_json
  if [[ "$MODE" == "weekly" ]]; then
    state_file_json="$(cat <<EOF
{
  "audit_root":"$STATE_ROOT",
  "tool_health_json":"${TOOL_HEALTH_JSON}",
  "tool_health_lines":"${TOOL_HEALTH_LINES}",
  "audit_latest":"$AUDIT_WEEKLY_LATEST",
  "audit_history":"$AUDIT_WEEKLY_HISTORY",
  "legacy_state_roots":["$STATE_ROOT_LEGACY1","$STATE_ROOT_LEGACY2"]
}
EOF
)"
  else
    state_file_json="$(cat <<EOF
{
  "audit_root":"$STATE_ROOT",
  "tool_health_json":"${TOOL_HEALTH_JSON}",
  "tool_health_lines":"${TOOL_HEALTH_LINES}",
  "audit_latest":"$AUDIT_DAILY_LATEST",
  "audit_history":"$AUDIT_DAILY_HISTORY",
  "legacy_state_roots":["$STATE_ROOT_LEGACY1","$STATE_ROOT_LEGACY2"]
}
EOF
)"
  fi

  local timestamp
  local epoch
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  epoch="$(date -u +%s)"
  cat <<EOF
{
  "mode":"$MODE",
  "generated_at":"$timestamp",
  "generated_at_epoch":$epoch,
  "fleet_status":"$fleet_status",
  "summary":{
    "pass":$pass_count,
    "yellow":$warn_count,
    "red":$fail_count,
    "unknown":$unknown_count,
    "hosts_checked":$summary_hosts_checked,
    "hosts_failed":$hosts_failed
  },
  "hosts":$host_payload,
  "checks":$checks_json,
  "repair_hints":$repair_hints_json,
  "reason_codes":$reasons_json,
  "state_paths":$state_file_json,
  "slack_channel":"$(json_escape "$SLACK_CHANNEL")",
  "slack_message":"$(json_escape "$(render_slack_text "$fleet_status" "$hosts_failed")")"
}
EOF
}

save_audit_artifact() {
  local payload="$1"
  local latest="$AUDIT_DAILY_LATEST"
  local history_dir="$AUDIT_DAILY_HISTORY"
  if [[ "$MODE" == "weekly" ]]; then
    latest="$AUDIT_WEEKLY_LATEST"
    history_dir="$AUDIT_WEEKLY_HISTORY"
  fi
  local history
  mkdir -p "$history_dir"
  if [[ "$MODE" == "daily" ]]; then
    history="${history_dir}/$(date -u +%Y-%m-%d).json"
  else
    history="${history_dir}/$(date -u +%G-%V).json"
  fi
  write_atomic "$latest" "$payload"
  write_atomic "$history" "$payload"
}

load_args_state() {
  TOOL_HEALTH_JSON="${TOOL_HEALTH_JSON:-${STATE_ROOT}/tool-health.json}"
  TOOL_HEALTH_LINES="${TOOL_HEALTH_LINES:-${STATE_ROOT}/tool-health.lines}"
  AUDIT_DAILY_LATEST="${AUDIT_DAILY_LATEST:-${STATE_ROOT}/audit/daily/latest.json}"
  AUDIT_DAILY_HISTORY="${AUDIT_DAILY_HISTORY:-${STATE_ROOT}/audit/daily/history}"
  AUDIT_WEEKLY_LATEST="${AUDIT_WEEKLY_LATEST:-${STATE_ROOT}/audit/weekly/latest.json}"
  AUDIT_WEEKLY_HISTORY="${AUDIT_WEEKLY_HISTORY:-${STATE_ROOT}/audit/weekly/history}"

  reason_codes=()
  checks=()
  pass_count=0
  warn_count=0
  fail_count=0
  unknown_count=0
  host_order=()
  host_overall=()
  host_checks=()

  gather_checks

  local payload
  payload="$(render_payload)"
  mkdir -p "${STATE_ROOT}/audit/$MODE"
  if [[ "$STATE_ONLY" -eq 0 ]]; then
    save_audit_artifact "$payload"
  fi
  if [[ "$OUTPUT_SLACK" -eq 1 ]]; then
    printf '%s\n' "$(echo "$payload" | sed -n 's/.*"slack_message":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g')"
  else
    printf '%s\n' "$payload"
  fi
  local fleet_status
  fleet_status="$(printf '%s\n' "$payload" | sed -n 's/.*"fleet_status":[[:space:]]*"\([a-z]*\)".*/\1/p')"
  if [[ "$fleet_status" == "red" ]]; then
    return 2
  fi
  return 0
}

TOOL_STALE_HOURS=6
DOLT_STALE_MINUTES=15
UNKNOWN_HOST_ESCALATION_RUNS=3
parse_args "$@"
load_manifest_config
load_args_state
exit $?
