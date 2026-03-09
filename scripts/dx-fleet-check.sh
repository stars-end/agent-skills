#!/usr/bin/env bash
#
# dx-fleet-check.sh
#
# Fleet health probe for Fleet Sync runtime/governance checks.
# Supports cross-VM aggregation for both daily and weekly modes.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_ROOT="${DX_FLEET_STATE_ROOT:-${HOME}/.dx-state/fleet}"
STATE_JSON="${STATE_ROOT}/tool-health.json"
STATE_LINES="${STATE_ROOT}/tool-health.lines"
MCP_TOOLS_SYNC_JSON="${STATE_ROOT}/mcp-tools-sync.json"
OUTPUT_FORMAT="text"
LOCAL_ONLY=0
MODE="daily"

STATE_ROOT_LEGACY1="${HOME}/.dx-state/fleet-sync"
STATE_ROOT_LEGACY2="${HOME}/.dx-state/fleet_sync"
SNAPSHOT_STALE_SECONDS=21600

# shellcheck disable=SC1091
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/dx-slack-alerts.sh" 2>/dev/null || true

DAILY_CHECK_IDS=(
  beads_dolt
  tool_mcp_health
  required_service_health
  op_auth_readiness
  alerts_transport_readiness
)

WEEKLY_CHECK_IDS=(
  canonical_repo_hygiene
  skills_symlink_integrity
  skills_plane_alignment
  ide_bootstrap_alignment
  global_constraints_rails
  ide_config_presence_and_drift
  cron_health
  service_cap_and_forbidden_components
  deployment_stack_readiness
  railway_auth_context
  gh_deploy_readiness
)

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

usage() {
  cat <<'USAGE'
Usage: dx-fleet-check.sh [--mode daily|weekly] [--json] [--state-dir PATH] [--local-only]
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="$2"
        shift 2
        ;;
      --daily)
        MODE="daily"
        shift
        ;;
      --weekly)
        MODE="weekly"
        shift
        ;;
      --json)
        OUTPUT_FORMAT="json"
        shift
        ;;
      --state-dir)
        STATE_ROOT="$2"
        STATE_JSON="${STATE_ROOT}/tool-health.json"
        STATE_LINES="${STATE_ROOT}/tool-health.lines"
        MCP_TOOLS_SYNC_JSON="${STATE_ROOT}/mcp-tools-sync.json"
        shift 2
        ;;
      --local-only)
        LOCAL_ONLY=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown flag: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

load_thresholds() {
  local manifest="${SCRIPT_DIR}/../configs/fleet-sync.manifest.yaml"
  [[ -f "$manifest" ]] || return 0
  local value
  value="$(python3 - <<'PY' "$manifest" 2>/dev/null || true
import sys, yaml
p=sys.argv[1]
try:
    data=yaml.safe_load(open(p, 'r', encoding='utf-8')) or {}
except Exception:
    print('')
    raise SystemExit(0)
a=(data.get('audit') or {})
t=(a.get('thresholds') or {})
v=t.get('tool_stale_hours', '')
print(v)
PY
)"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    SNAPSHOT_STALE_SECONDS=$((value * 3600))
  fi
}

fleet_local_host() {
  if [[ -n "${CANONICAL_HOST_KEY:-}" ]]; then
    case "${CANONICAL_HOST_KEY}" in
      macmini|homedesktop-wsl|epyc6|epyc12)
        echo "${CANONICAL_HOST_KEY}"
        return 0
        ;;
    esac
  fi
  local current_host
  current_host="$(hostname -s 2>/dev/null | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]')"
  if [[ "$current_host" =~ macmini ]]; then
    echo "macmini"
  elif [[ "$current_host" =~ homedesktop ]]; then
    echo "homedesktop-wsl"
  elif [[ "$current_host" =~ epyc12 ]]; then
    echo "epyc12"
  elif [[ "$current_host" =~ epyc6 ]]; then
    echo "epyc6"
  else
    echo "local"
  fi
}

normalize_host_key() {
  local target="$1"
  target="${target##*/}"
  target="${target%%:*}"
  printf '%s' "${target##*@}"
}

canonical_host_to_target() {
  local host_key="$1"
  local entry
  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      if [[ "$(normalize_host_key "$entry")" == "$host_key" ]]; then
        printf '%s\n' "${entry%%:*}"
        return 0
      fi
    done
  fi
  echo "${USER:-fengning}@${host_key}"
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

collect_hosts() {
  local local_host="$1"
  if [[ "$LOCAL_ONLY" -eq 1 ]] || [[ "${DX_FLEET_LOCAL_ONLY:-0}" == "1" ]]; then
    echo "$local_host"
    return 0
  fi

  local -a hosts=()
  local entry host
  if declare -p CANONICAL_VMS >/dev/null 2>&1 && [[ "${#CANONICAL_VMS[@]}" -gt 0 ]]; then
    for entry in "${CANONICAL_VMS[@]}"; do
      host="$(normalize_host_key "$entry")"
      [[ -n "$host" ]] && hosts+=("$host")
    done
  else
    hosts=(macmini homedesktop-wsl epyc6 epyc12)
  fi

  echo "$local_host"
  local seen="$local_host"
  for host in "${hosts[@]}"; do
    [[ "$host" == "$local_host" ]] && continue
    if [[ " $seen " == *" $host "* ]]; then
      continue
    fi
    seen+=" $host"
    echo "$host"
  done
}

host_role_for_check() {
  local host="$1"
  case "$host" in
    macmini) echo "macmini" ;;
    homedesktop-wsl) echo "homedesktop-wsl" ;;
    epyc12) echo "epyc12" ;;
    epyc6) echo "epyc6" ;;
    *) echo "${CANONICAL_HOST_KEY:-$host}" ;;
  esac
}

required_tools_for_host() {
  local host_key="$1"
  case "$host_key" in
    macmini|homedesktop-wsl)
      printf '%s\n' bd gh git railway op mise ru
      ;;
    *)
      printf '%s\n' bd gh git railway op mise
      ;;
  esac
}

normalize_status() {
  local status="$1"
  case "$status" in
    pass|green) echo pass ;;
    warn|yellow) echo warn ;;
    fail|red) echo fail ;;
    *) echo unknown ;;
  esac
}

json_array_from_rows() {
  if [[ "$#" -eq 0 ]]; then
    echo "[]"
    return
  fi
  local out="["
  local first=1
  local row
  for row in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      out+="$row"
      first=0
    else
      out+=",$row"
    fi
  done
  out+="]"
  echo "$out"
}

json_array_from_strings() {
  local out="["
  local first=1
  local item
  for item in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      out+=","
    fi
    out+="\"$(json_escape "$item")\""
  done
  out+="]"
  echo "$out"
}

json_array_from_objects() {
  local out="["
  local first=1
  local item
  for item in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      out+=","
    fi
    out+="$item"
  done
  out+="]"
  echo "$out"
}

mcp_tools_sync_status() {
  local status="fail"
  local severity="high"
  local details="dx-mcp-tools-sync check failed"
  local tools_fail=0

  local out=""
  if [[ -x "$SCRIPT_DIR/dx-mcp-tools-sync.sh" ]]; then
    if out="$($SCRIPT_DIR/dx-mcp-tools-sync.sh --check --json --state-dir "$STATE_ROOT" 2>/dev/null || true)"; then
      :
    fi
  fi

  if [[ -n "$out" ]] && command -v jq >/dev/null 2>&1; then
    # STRICT INTERPRETATION: Check tools_fail count
    tools_fail="$(printf '%s' "$out" | jq -r '.summary.tools_fail // 0' 2>/dev/null || echo 0)"
    if [[ "$tools_fail" -gt 0 ]]; then
      status="fail"
      severity="high"
      details="MCP tools health fail: tools_fail=$tools_fail"
      printf '%s|%s|%s' "$status" "$severity" "$details"
      return
    fi

    # Check overall status (fail-closed: never trust green if tools failed)
    status="$(printf '%s' "$out" | jq -r '.overall // .status // "red"' 2>/dev/null || echo red)"
    details="$(printf '%s' "$out" | jq -r '.details // "mcp-tools-sync state"' 2>/dev/null || echo 'mcp-tools-sync state')"
    
    # FRESHNESS CHECK: Verify snapshot is not stale
    local generated_epoch now age
    generated_epoch="$(printf '%s' "$out" | jq -r '.generated_at_epoch // 0' 2>/dev/null || echo 0)"
    now="$(date -u +%s)"
    
    if [[ "$generated_epoch" =~ ^[0-9]+$ ]]; then
      age=$((now - generated_epoch))
      if [[ "$age" -gt "$SNAPSHOT_STALE_SECONDS" ]]; then
        status="fail"
        severity="high"
        details="local_snapshot_stale: age=${age}s threshold=${SNAPSHOT_STALE_SECONDS}s"
        printf '%s|%s|%s' "$status" "$severity" "$details"
        return
      fi
    fi
  fi

  case "$status" in
    green|pass) status="pass"; severity="low" ;;
    yellow|warn) status="warn" ;;
    red|fail) status="fail" ;;
    *) status="unknown" ;;
  esac

  printf '%s|%s|%s' "$status" "$severity" "$details"
}

check_beads_dolt() {
  local status="pass" severity="low" details="Beads runtime ready"
  if ! command -v bd >/dev/null 2>&1; then
    status="fail"; severity="high"; details="bd binary missing"
  elif ! bd dolt test --json >/dev/null 2>&1; then
    status="fail"; severity="high"; details="bd dolt test failed"
  fi
  echo "$status|$severity|$details"
}

check_required_service_health() {
  local host_role="$1"
  local missing=()
  local tool
  while IFS= read -r tool; do
    [[ -z "$tool" ]] && continue
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done < <(required_tools_for_host "$host_role")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "fail|medium|required tools missing: ${missing[*]}"
  else
    echo "pass|low|required tools present"
  fi
}

check_op_auth_readiness() {
  if command -v agent_coordination_load_op_token >/dev/null 2>&1 && agent_coordination_load_op_token >/dev/null 2>&1; then
    echo "pass|low|OP service-account token resolved"
    return
  fi
  if command -v op >/dev/null 2>&1 && [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && op whoami >/dev/null 2>&1; then
    echo "pass|low|OP service-account token verified"
    return
  fi
  if command -v op >/dev/null 2>&1; then
    echo "fail|medium|op installed but service-account token unavailable"
  else
    echo "fail|medium|op CLI missing"
  fi
}

check_alerts_transport_readiness() {
  if command -v agent_coordination_transport_ready >/dev/null 2>&1 && agent_coordination_transport_ready >/dev/null 2>&1; then
    echo "pass|low|deterministic Slack transport ready"
    return
  fi
  if [[ -n "${DX_SLACK_WEBHOOK:-}" || -n "${DX_ALERTS_WEBHOOK:-}" || -n "${SLACK_BOT_TOKEN:-}" ]]; then
    echo "pass|low|transport credentials detected"
  else
    echo "fail|medium|Slack transport credentials missing"
  fi
}

weekly_check_canonical_repo_hygiene() {
  local missing=0 dirty=0 offbranch=0 repo path branch
  for repo in "${CANONICAL_REQUIRED_REPOS[@]:-agent-skills prime-radiant-ai affordabot llm-common}"; do
    path="${HOME}/${repo}"
    if [[ ! -d "$path/.git" ]]; then
      missing=$((missing + 1))
      continue
    fi
    branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    [[ "$branch" != "${CANONICAL_TRUNK_BRANCH:-master}" ]] && offbranch=$((offbranch + 1))
    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null || true)" ]]; then
      dirty=$((dirty + 1))
    fi
  done
  if [[ "$missing" -gt 0 || "$dirty" -gt 0 || "$offbranch" -gt 0 ]]; then
    echo "fail|high|repo hygiene drift: missing=$missing dirty=$dirty offbranch=$offbranch"
  else
    echo "pass|low|canonical repos on ${CANONICAL_TRUNK_BRANCH:-master} and clean"
  fi
}

weekly_check_skills_symlink() {
  local target="${HOME}/.agent/skills"
  if [[ -L "$target" ]] && [[ "$(readlink "$target")" == *"agent-skills"* ]]; then
    echo "pass|low|~/.agent/skills symlinked to agent-skills"
  else
    echo "fail|medium|~/.agent/skills symlink missing or non-canonical"
  fi
}

weekly_check_skills_plane_alignment() {
  local target="${AGENT_SKILLS_DIR:-${HOME}/.agent/skills}"
  local failures=()

  # Check 1: Skills plane exists
  if [[ ! -e "$target" ]]; then
    failures+=("skills_plane_missing:$target")
  fi

  # Check 2: Symlink or git checkout
  if [[ -L "$target" ]]; then
    local link_target
    link_target="$(readlink -f "$target" 2>/dev/null || readlink "$target" 2>/dev/null || true)"
    if [[ "$link_target" != *"agent-skills"* ]]; then
      failures+=("symlink_non_canonical:$link_target")
    fi
  elif [[ -d "$target/.git" ]]; then
    : # Git checkout is acceptable
  elif [[ -d "$target" ]]; then
    failures+=("not_symlink_not_git")
  fi

  # Check 3: AGENTS.md exists
  if [[ ! -f "$target/AGENTS.md" ]]; then
    failures+=("AGENTS.md_missing")
  fi

  # Check 4: Baseline artifact exists
  if [[ ! -f "$target/dist/universal-baseline.md" ]]; then
    failures+=("baseline_missing")
  fi

  # Check 5: Core skill directories exist
  local core_dirs=("core" "extended" "health" "infra" "railway")
  for dir in "${core_dirs[@]}"; do
    if [[ ! -d "$target/$dir" ]]; then
      failures+=("core_dir_missing:$dir")
    fi
  done

  if [[ ${#failures[@]} -eq 0 ]]; then
    local sha=""
    if [[ -d "$target/.git" ]]; then
      sha="$(git -C "$target" rev-parse --short HEAD 2>/dev/null || true)"
    fi
    if [[ -n "$sha" ]]; then
      echo "pass|low|skills plane aligned (SHA: $sha)"
    else
      echo "pass|low|skills plane aligned"
    fi
  else
    echo "fail|high|skills plane misaligned: ${failures[*]}"
  fi
}

weekly_check_ide_bootstrap_alignment() {
  local skills_target="${AGENT_SKILLS_DIR:-${HOME}/.agent/skills}"
  local failures=()
  local warnings=()

  # Check IDE config files that should point at skills plane
  # These are determined by canonical-targets.sh

  # Claude Code: CLAUDE.md should exist in home and point at AGENTS.md
  if [[ -f "${HOME}/.claude/CLAUDE.md" ]]; then
    if [[ -L "${HOME}/.claude/CLAUDE.md" ]]; then
      local claude_link
      claude_link="$(readlink "${HOME}/.claude/CLAUDE.md" 2>/dev/null || true)"
      if [[ "$claude_link" != *".agent/skills/AGENTS.md"* ]] && [[ "$claude_link" != *"agent-skills/AGENTS.md"* ]]; then
        warnings+=("claude_md_non_canonical_link")
      fi
    else
      # Could be a file with content pointing at AGENTS.md
      if ! grep -q "AGENTS.md" "${HOME}/.claude/CLAUDE.md" 2>/dev/null; then
        warnings+=("claude_md_no_agents_ref")
      fi
    fi
  else
    # Claude Code may not be installed on all hosts
    warnings+=("claude_md_missing")
  fi

  # Gemini CLI: GEMINI.md should point at AGENTS.md
  if [[ -f "${HOME}/.gemini/GEMINI.md" ]]; then
    if [[ -L "${HOME}/.gemini/GEMINI.md" ]]; then
      local gemini_link
      gemini_link="$(readlink "${HOME}/.gemini/GEMINI.md" 2>/dev/null || true)"
      if [[ "$gemini_link" != *".agent/skills/AGENTS.md"* ]] && [[ "$gemini_link" != *"agent-skills/AGENTS.md"* ]]; then
        warnings+=("gemini_md_non_canonical_link")
      fi
    fi
  else
    warnings+=("gemini_md_missing")
  fi

  # OpenCode: config.json should reference AGENTS.md
  if [[ -f "${HOME}/.opencode/config.json" ]]; then
    if ! grep -q "AGENTS.md" "${HOME}/.opencode/config.json" 2>/dev/null; then
      warnings+=("opencode_no_agents_ref")
    fi
  else
    warnings+=("opencode_config_missing")
  fi

  # Failures indicate broken bootstrap, warnings indicate missing/non-canonical
  if [[ ${#failures[@]} -gt 0 ]]; then
    echo "fail|high|IDE bootstrap failures: ${failures[*]}"
  elif [[ ${#warnings[@]} -gt 3 ]]; then
    # Many warnings likely means IDEs not installed on this host
    echo "pass|low|IDE bootstrap: ${#warnings[@]} warnings (IDEs may not be installed)"
  elif [[ ${#warnings[@]} -gt 0 ]]; then
    echo "warn|medium|IDE bootstrap warnings: ${warnings[*]}"
  else
    echo "pass|low|IDE bootstrap rails aligned"
  fi
}

weekly_check_global_constraints() {
  if [[ -x "$SCRIPT_DIR/dx-ide-global-constraints-install.sh" ]] && "$SCRIPT_DIR/dx-ide-global-constraints-install.sh" --check >/dev/null 2>&1; then
    echo "pass|low|global constraints rails present"
  else
    echo "fail|medium|global constraints rails check failed"
  fi
}

weekly_check_ide_config_drift() {
  local missing=()
  local ide artifact
  for ide in "${CANONICAL_IDES[@]:-}"; do
    while IFS= read -r artifact; do
      [[ -z "$artifact" ]] && continue
      [[ -f "$artifact" ]] || missing+=("${ide}:${artifact}")
    done < <(get_ide_artifacts "$ide" 2>/dev/null || true)
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "fail|high|missing canonical IDE artifacts: ${missing[*]}"
    return
  fi

  local mcp_status
  mcp_status="$(mcp_tools_sync_status)"
  IFS='|' read -r status _severity details <<<"$mcp_status"
  if [[ "$status" != "pass" ]]; then
    echo "fail|high|MCP drift: $details"
  else
    echo "pass|low|IDE artifacts and MCP config aligned"
  fi
}

weekly_check_cron_health() {
  if command -v crontab >/dev/null 2>&1 && crontab -l >/dev/null 2>&1; then
    echo "pass|low|crontab readable"
  else
    echo "fail|medium|crontab unavailable or unreadable"
  fi
}

weekly_check_service_cap() {
  local forbidden_count=0
  if command -v pgrep >/dev/null 2>&1; then
    forbidden_count="$(pgrep -fl 'supergateway|mcp-proxy' 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [[ "$forbidden_count" -gt 0 ]]; then
    echo "fail|high|forbidden gateway process detected count=$forbidden_count"
  else
    echo "pass|low|no forbidden gateway components"
  fi
}

weekly_check_deployment_stack() {
  local missing=()
  command -v railway >/dev/null 2>&1 || missing+=(railway)
  command -v gh >/dev/null 2>&1 || missing+=(gh)
  command -v op >/dev/null 2>&1 || missing+=(op)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "fail|medium|deployment stack missing: ${missing[*]}"
  else
    echo "pass|low|deployment stack tools present"
  fi
}

weekly_check_railway_auth() {
  if ! command -v railway >/dev/null 2>&1; then
    echo "fail|medium|railway CLI missing"
    return
  fi
  if railway whoami >/dev/null 2>&1; then
    echo "pass|low|railway auth verified"
    return
  fi

  if command -v op >/dev/null 2>&1; then
    local token
    token="$(op read 'op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN' 2>/dev/null || true)"
    if [[ -n "$token" ]] && RAILWAY_API_TOKEN="$token" railway whoami >/dev/null 2>&1; then
      echo "pass|low|railway auth verified via OP token hydration"
      return
    fi
  fi

  echo "fail|high|railway auth unavailable"
}

weekly_check_gh_readiness() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "pass|low|gh auth verified"
  else
    echo "fail|medium|gh missing or unauthenticated"
  fi
}

build_local_rows() {
  local host="$1"
  local role="$2"
  local -a rows=()
  local pass_count=0 warn_count=0 fail_count=0 unknown_count=0

  local add_row
  add_row() {
    local id="$1" st="$2" sv="$3" dt="$4"
    rows+=("{\"id\":\"$id\",\"status\":\"$(json_escape "$st")\",\"severity\":\"$(json_escape "$sv")\",\"details\":\"$(json_escape "$dt")\"}")
    case "$st" in
      pass) pass_count=$((pass_count + 1)) ;;
      warn) warn_count=$((warn_count + 1)) ;;
      fail) fail_count=$((fail_count + 1)) ;;
      *) unknown_count=$((unknown_count + 1)) ;;
    esac
  }

  local status severity details
  if [[ "$MODE" == "daily" ]]; then
    IFS='|' read -r status severity details <<<"$(check_beads_dolt)"
    add_row "beads_dolt" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(mcp_tools_sync_status)"
    add_row "tool_mcp_health" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(check_required_service_health "$role")"
    add_row "required_service_health" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(check_op_auth_readiness)"
    add_row "op_auth_readiness" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(check_alerts_transport_readiness)"
    add_row "alerts_transport_readiness" "$status" "$severity" "$details"
  else
    IFS='|' read -r status severity details <<<"$(weekly_check_canonical_repo_hygiene)"
    add_row "canonical_repo_hygiene" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_skills_symlink)"
    add_row "skills_symlink_integrity" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_skills_plane_alignment)"
    add_row "skills_plane_alignment" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_ide_bootstrap_alignment)"
    add_row "ide_bootstrap_alignment" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_global_constraints)"
    add_row "global_constraints_rails" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_ide_config_drift)"
    add_row "ide_config_presence_and_drift" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_cron_health)"
    add_row "cron_health" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_service_cap)"
    add_row "service_cap_and_forbidden_components" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_deployment_stack)"
    add_row "deployment_stack_readiness" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_railway_auth)"
    add_row "railway_auth_context" "$status" "$severity" "$details"

    IFS='|' read -r status severity details <<<"$(weekly_check_gh_readiness)"
    add_row "gh_deploy_readiness" "$status" "$severity" "$details"
  fi

  local overall="green"
  if [[ "$fail_count" -gt 0 ]]; then
    overall="red"
  elif [[ "$warn_count" -gt 0 ]]; then
    overall="yellow"
  fi

  local rows_json
  rows_json="$(json_array_from_rows "${rows[@]-}")"
  echo "$overall|$pass_count|$warn_count|$fail_count|$unknown_count|$rows_json"
}

expected_ids_csv() {
  if [[ "$MODE" == "daily" ]]; then
    local IFS=,
    echo "${DAILY_CHECK_IDS[*]}"
  else
    local IFS=,
    echo "${WEEKLY_CHECK_IDS[*]}"
  fi
}

build_missing_rows() {
  local host="$1"
  local reason_code="$2"
  local reason_detail="$3"
  local -a rows=()
  local id
  local -a ids=()
  if [[ "$MODE" == "daily" ]]; then
    ids=("${DAILY_CHECK_IDS[@]}")
  else
    ids=("${WEEKLY_CHECK_IDS[@]}")
  fi
  for id in "${ids[@]}"; do
    rows+=("{\"id\":\"$id\",\"status\":\"fail\",\"severity\":\"high\",\"details\":\"$(json_escape "$reason_detail")\",\"reason_code\":\"$(json_escape "$reason_code")\"}")
  done
  local rows_json
  rows_json="$(json_array_from_rows "${rows[@]}")"
  echo "red|0|0|${#ids[@]}|0|$rows_json|$reason_code"
}

remote_host_payload() {
  local host="$1"
  local target="$2"
  local remote_script="${REPO_ROOT}/scripts/dx-fleet-check.sh"
  local remote_script_alt="${remote_script#/private}"
  local cmd
  cmd="SCRIPT='${remote_script}'; ALT='${remote_script_alt}'; if [ ! -x \"\$SCRIPT\" ] && [ -x \"\$ALT\" ]; then SCRIPT=\"\$ALT\"; fi; if [ ! -x \"\$SCRIPT\" ]; then SCRIPT=~/agent-skills/scripts/dx-fleet-check.sh; fi; STATE_DIR=\"\$HOME/.dx-state/fleet\"; DX_FLEET_STATE_ROOT=\"\$STATE_DIR\" \"\$SCRIPT\" --mode ${MODE} --local-only --json --state-dir \"\$STATE_DIR\""
  ssh_canonical_vm "$target" "$cmd" 2>/dev/null || true
}

parse_remote_rows() {
  local payload="$1"
  local host="$2"

  if ! command -v jq >/dev/null 2>&1; then
    build_missing_rows "$host" "remote_snapshot_unparseable" "jq required to parse remote payload"
    return 0
  fi

  # FRESHNESS CHECK
  local now epoch age
  now="$(date -u +%s)"
  epoch="$(printf '%s' "$payload" | jq -r '.generated_at_epoch // 0' 2>/dev/null || echo 0)"
  if ! [[ "$epoch" =~ ^[0-9]+$ ]]; then
    epoch=0
  fi
  age=$((now - epoch))
  if [[ "$age" -gt "$SNAPSHOT_STALE_SECONDS" ]]; then
    build_missing_rows "$host" "remote_snapshot_stale" "remote snapshot stale age=${age}s threshold=${SNAPSHOT_STALE_SECONDS}s"
    return 0
  fi

  # STRICT MCP TOOLS FAIL CHECK: Check if tool_mcp_health has tools_fail > 0
  local mcp_check
  mcp_check="$(printf '%s' "$payload" | jq -r '.hosts[0].checks[] | select(.id == "tool_mcp_health") | .details // ""' 2>/dev/null || true)"
  if [[ "$mcp_check" =~ "MCP tools health fail" ]] || [[ "$mcp_check" =~ "tools_fail=" ]]; then
    # Extract tools_fail count if present
    local tools_fail_count
    tools_fail_count="$(echo "$mcp_check" | grep -oE 'tools_fail=[0-9]+' | cut -d= -f2 || echo 0)"
    if [[ "$tools_fail_count" -gt 0 ]]; then
      build_missing_rows "$host" "mcp_tools_fail" "remote MCP tools health fail: $mcp_check"
      return 0
    fi
  fi

  local expected ids_json
  expected="$(expected_ids_csv)"
  ids_json="$(printf '%s' "$expected" | awk 'BEGIN{RS=","; ORS=""} {gsub(/^[[:space:]]+|[[:space:]]+$/,""); if(length($0)>0){printf "%s\"%s\"", (NR>1?",":""), $0}}')"
  ids_json="[$ids_json]"

  local parsed
  parsed="$(printf '%s' "$payload" | jq -c --arg host "$host" --argjson ids "$ids_json" '
    def norm($s):
      if $s == "green" or $s == "pass" then "pass"
      elif $s == "yellow" or $s == "warn" then "warn"
      elif $s == "red" or $s == "fail" then "fail"
      else "unknown" end;
    . as $root
    | (($root.hosts[0].checks // []) | map(.id = ((.id // "") | tostring | sub("^fleet\\.v2\\.2\\.";"")))) as $rows
    | ($ids | map(
        . as $id |
        (($rows | map(select(.id == $id))[0]) // {
          id: $id,
          status: "fail",
          severity: "high",
          details: "missing check in remote payload"
        })
      )) as $final
    | {
        overall: (if ($final | map(norm(.status)) | any(. == "fail")) then "red" elif ($final | map(norm(.status)) | any(. == "warn")) then "yellow" else "green" end),
        pass: ($final | map(norm(.status)) | map(select(.=="pass")) | length),
        warn: ($final | map(norm(.status)) | map(select(.=="warn")) | length),
        fail: ($final | map(norm(.status)) | map(select(.=="fail")) | length),
        unknown: ($final | map(norm(.status)) | map(select(.=="unknown")) | length),
        rows: ($final | map({id:.id,status:norm(.status),severity:(.severity // "medium"),details:(.details // "")}))
      }
  ' 2>/dev/null || true)"

  if [[ -z "$parsed" ]]; then
    build_missing_rows "$host" "remote_snapshot_unparseable" "unable to parse remote payload"
    return 0
  fi

  local overall pass warn fail unknown rows
  overall="$(printf '%s' "$parsed" | jq -r '.overall')"
  pass="$(printf '%s' "$parsed" | jq -r '.pass')"
  warn="$(printf '%s' "$parsed" | jq -r '.warn')"
  fail="$(printf '%s' "$parsed" | jq -r '.fail')"
  unknown="$(printf '%s' "$parsed" | jq -r '.unknown')"
  rows="$(printf '%s' "$parsed" | jq -c '.rows')"

  echo "$overall|$pass|$warn|$fail|$unknown|$rows|ok"
}

main() {
  parse_args "$@"
  load_thresholds

  if [[ "$MODE" != "daily" && "$MODE" != "weekly" ]]; then
    echo "Invalid --mode: $MODE" >&2
    exit 2
  fi

  mkdir -p "$STATE_ROOT"

  local timestamp timestamp_epoch local_host
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  timestamp_epoch="$(date -u +%s)"
  local_host="$(fleet_local_host)"

  local hosts_checked=0 hosts_failed=0
  local total_pass=0 total_warn=0 total_fail=0 total_unknown=0
  local fleet_status="green"

  local host_records=""
  local checks_flat=""
  local first_host=1
  local -a reason_codes=()
  local -a repair_hints=()

  local host
  for host in $(collect_hosts "$local_host"); do
    local role row_payload
    role="$(host_role_for_check "$host")"

    if [[ "$host" == "$local_host" ]]; then
      row_payload="$(build_local_rows "$host" "$role")"
    else
      local target payload
      target="$(canonical_host_to_target "$host")"
      payload="$(remote_host_payload "$host" "$target")"
      if [[ -z "$payload" ]]; then
        row_payload="$(build_missing_rows "$host" "remote_snapshot_missing" "unable to fetch remote snapshot from $target")"
        reason_codes+=("remote_snapshot_missing")
      else
        row_payload="$(parse_remote_rows "$payload" "$host")"
      fi
    fi

    hosts_checked=$((hosts_checked + 1))
    IFS='|' read -r host_overall host_pass host_warn host_fail host_unknown host_rows host_reason <<<"$row_payload"
    if [[ -n "${host_reason:-}" && "${host_reason}" != "ok" ]]; then
      reason_codes+=("$host_reason")
    fi

    if [[ "$host_overall" == "red" ]]; then
      hosts_failed=$((hosts_failed + 1))
      fleet_status="red"
      repair_hints+=("{\"host\":\"$host\",\"check_id\":\"fleet.v2.2.host_red\",\"command\":\"ssh ${USER:-fengning}@$host '~/agent-skills/scripts/dx-fleet-repair.sh --json --state-dir $STATE_ROOT'\"}")
    elif [[ "$host_overall" == "yellow" && "$fleet_status" != "red" ]]; then
      fleet_status="yellow"
      repair_hints+=("{\"host\":\"$host\",\"check_id\":\"fleet.v2.2.host_yellow\",\"command\":\"ssh ${USER:-fengning}@$host '~/agent-skills/scripts/dx-fleet-repair.sh --json --state-dir $STATE_ROOT'\"}")
    fi

    total_pass=$((total_pass + host_pass))
    total_warn=$((total_warn + host_warn))
    total_fail=$((total_fail + host_fail))
    total_unknown=$((total_unknown + host_unknown))

    local host_record
    host_record="{\"host\":\"$host\",\"overall\":\"$host_overall\",\"checks\":$host_rows}"
    if [[ "$first_host" -eq 1 ]]; then
      host_records+="$host_record"
      checks_flat+="$(printf '%s' "$host_rows" | sed -e 's/^\[//' -e 's/\]$//')"
      first_host=0
    else
      host_records+=",$host_record"
      local stripped
      stripped="$(printf '%s' "$host_rows" | sed -e 's/^\[//' -e 's/\]$//')"
      if [[ -n "$stripped" ]]; then
        [[ -n "$checks_flat" ]] && checks_flat+="," || true
        checks_flat+="$stripped"
      fi
    fi
  done

  local reason_codes_json repair_hints_json
  if [[ ${#reason_codes[@]} -eq 0 ]]; then
    reason_codes_json='["ok"]'
  else
    local -a deduped=()
    local code
    for code in "${reason_codes[@]}"; do
      is_member "$code" "${deduped[@]-}" || deduped+=("$code")
    done
    reason_codes_json="$(json_array_from_strings "${deduped[@]-}")"
  fi
  if [[ ${#repair_hints[@]} -eq 0 ]]; then
    repair_hints_json='[]'
  else
    repair_hints_json="$(json_array_from_objects "${repair_hints[@]-}")"
  fi

  local result_json summary_json state_paths_json
  summary_json="{\"hosts_checked\":$hosts_checked,\"hosts_failed\":$hosts_failed,\"checks\":{\"pass\":$total_pass,\"warn\":$total_warn,\"fail\":$total_fail,\"unknown\":$total_unknown}}"
  state_paths_json="{\"tool_health_json\":\"${STATE_JSON}\",\"tool_health_lines\":\"${STATE_LINES}\",\"mcp_tools_sync_json\":\"${MCP_TOOLS_SYNC_JSON}\",\"audit_daily_latest\":\"${STATE_ROOT}/audit/daily/latest.json\",\"audit_weekly_latest\":\"${STATE_ROOT}/audit/weekly/latest.json\",\"legacy_state_roots\":[\"${STATE_ROOT_LEGACY1}\",\"${STATE_ROOT_LEGACY2}\"]}"

  result_json="{\"mode\":\"$MODE\",\"generated_at\":\"$timestamp\",\"generated_at_epoch\":$timestamp_epoch,\"fleet_status\":\"$fleet_status\",\"summary\":$summary_json,\"hosts\":[${host_records}],\"checks\":[${checks_flat}],\"repair_hints\":$repair_hints_json,\"reason_codes\":$reason_codes_json,\"state_paths\":$state_paths_json}"

  if [[ "$MODE" == "daily" ]]; then
    write_atomic "$STATE_JSON" "$result_json"
    write_atomic "$STATE_LINES" "generated_at=$timestamp\ngenerated_at_epoch=$timestamp_epoch\nfleet_status=$fleet_status\nhosts_checked=$hosts_checked\nhosts_failed=$hosts_failed\nchecks_pass=$total_pass\nchecks_warn=$total_warn\nchecks_fail=$total_fail\nchecks_unknown=$total_unknown"
  else
    write_atomic "${STATE_ROOT}/weekly-health.json" "$result_json"
  fi

  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    printf '%s\n' "$result_json"
  else
    echo "🔍 DX Fleet Check ($MODE)"
    echo "generated_at=$timestamp"
    echo "fleet_status=$fleet_status"
    echo "hosts_checked=$hosts_checked"
    echo "hosts_failed=$hosts_failed"
    echo "checks_pass=$total_pass checks_warn=$total_warn checks_fail=$total_fail checks_unknown=$total_unknown"
  fi

  if [[ "$fleet_status" == "red" ]]; then
    exit 1
  fi
  if [[ "$fleet_status" == "yellow" ]]; then
    exit 2
  fi
  exit 0
}

main "$@"
