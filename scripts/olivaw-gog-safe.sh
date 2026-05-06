#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_DEFAULT="fengning@stars-end.ai"
CLIENT_DEFAULT="olivaw-gog"
STATE_FILE_DEFAULT="${HOME}/.hermes/profiles/olivaw/google-ops-state.env"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <gog-subcommand> [args...]" >&2
  exit 2
fi

if ! command -v gog >/dev/null 2>&1; then
  echo "blocked: gog binary not found" >&2
  exit 127
fi

family="$1"
command_name="${2:-}"
STATE_FILE="${OLIVAW_GOOGLE_STATE:-${STATE_FILE_DEFAULT}}"

gog_base=(gog --client "${CLIENT_DEFAULT}" --account "${ACCOUNT_DEFAULT}" --gmail-no-send --no-input)

load_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
  fi
}

require_state() {
  load_state
  if [[ -z "${OLIVAW_OPS_ROOT_ID:-}" || -z "${OLIVAW_TRACKER_SHEET_ID:-}" || -z "${OLIVAW_CALENDAR_ID:-}" ]]; then
    echo "blocked: olivaw google state is missing; run olivaw-google-ops-bootstrap.sh first (${STATE_FILE})" >&2
    exit 10
  fi
}

csv_contains() {
  local csv="$1"
  local needle="$2"
  local item
  IFS=',' read -r -a _items <<<"${csv}"
  for item in "${_items[@]}"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

arg_value() {
  local name="$1"
  shift
  local prev=""
  local arg
  for arg in "$@"; do
    if [[ "${prev}" == "${name}" ]]; then
      printf '%s\n' "${arg}"
      return 0
    fi
    if [[ "${arg}" == "${name}="* ]]; then
      printf '%s\n' "${arg#*=}"
      return 0
    fi
    prev="${arg}"
  done
  return 1
}

has_arg() {
  local name="$1"
  shift
  local arg
  for arg in "$@"; do
    [[ "${arg}" == "${name}" || "${arg}" == "${name}="* ]] && return 0
  done
  return 1
}

block_if_arg() {
  local name="$1"
  shift
  if has_arg "${name}" "$@"; then
    echo "blocked: argument ${name} is not allowed by Olivaw Google policy" >&2
    exit 10
  fi
}

folder_allowed() {
  local folder_id="$1"
  [[ -n "${folder_id}" ]] || return 1
  csv_contains "${OLIVAW_ALLOWED_FOLDER_IDS:-}" "${folder_id}"
}

drive_file_in_allowed_folder() {
  local file_id="$1"
  local parent_ids
  parent_ids="$("${gog_base[@]}" drive get "${file_id}" --json 2>/dev/null | jq -r '(.parents // .file.parents // [])[]?')" || return 1
  local parent_id
  while IFS= read -r parent_id; do
    folder_allowed "${parent_id}" && return 0
  done <<<"${parent_ids}"
  return 1
}

range_tab() {
  local range="$1"
  if [[ "${range}" == *"!"* ]]; then
    local tab="${range%%!*}"
    tab="${tab#\'}"
    tab="${tab%\'}"
    printf '%s\n' "${tab}"
  else
    printf '%s\n' "${range}"
  fi
}

tab_allowed() {
  local tab="$1"
  csv_contains "${OLIVAW_TRACKER_TABS:-}" "${tab}"
}

subject_has_olivaw_prefix() {
  local subject="$1"
  [[ "${subject}" == "[Olivaw"* ]]
}

event_summary_allowed() {
  local summary="$1"
  [[ "${summary}" == "[Olivaw "* || "${summary}" == "[Olivaw]"* ]]
}

calendar_event_is_olivaw_owned() {
  local calendar_id="$1"
  local event_id="$2"
  local event
  event="$("${gog_base[@]}" calendar event "${calendar_id}" "${event_id}" --json 2>/dev/null)" || return 1
  jq -e '
    (.extendedProperties.private.olivaw_managed == "true")
    or ((.summary // "") | startswith("[Olivaw"))
  ' >/dev/null <<<"${event}"
}

ensure_no_external_calendar_effects() {
  block_if_arg "--attendees" "$@"
  block_if_arg "--add-attendee" "$@"
  block_if_arg "--with-meet" "$@"
  local send_updates
  send_updates="$(arg_value "--send-updates" "$@" || true)"
  if [[ -n "${send_updates}" && "${send_updates}" != "none" ]]; then
    echo "blocked: calendar send-updates must be none" >&2
    exit 10
  fi
}

allow_read_command() {
  local family="$1"
  local command_name="$2"

  case "${family}:${command_name}" in
    auth:doctor)
      return 0
      ;;
    gmail:search)
      return 0
      ;;
    calendar:calendars|calendar:events|calendar:event|calendar:raw|calendar:list|calendar:ls|calendar:search|calendar:freebusy|calendar:colors|calendar:conflicts|calendar:time|calendar:users)
      return 0
      ;;
    drive:ls|drive:search|drive:tree|drive:du|drive:inventory|drive:get|drive:raw|drive:drives|drive:url)
      return 0
      ;;
    docs:info|docs:get|docs:show|docs:cat|docs:text|docs:read|docs:export|docs:download|docs:dl|docs:structure|docs:struct|docs:raw|docs:list-tabs)
      return 0
      ;;
    sheets:get|sheets:read|sheets:show|sheets:metadata|sheets:info|sheets:export|sheets:download|sheets:dl|sheets:notes|sheets:links|sheets:hyperlinks|sheets:raw)
      return 0
      ;;
    contacts:list|contacts:ls|contacts:search|contacts:get|contacts:info|contacts:show|contacts:dedupe|contacts:raw)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if allow_read_command "${family}" "${command_name}"; then
  export GOG_ACCOUNT="${ACCOUNT_DEFAULT}"
  exec "${gog_base[@]}" "$@"
fi

require_state

case "${family}:${command_name}" in
  drive:upload)
    parent_id="$(arg_value "--parent" "$@" || true)"
    if ! folder_allowed "${parent_id}"; then
      echo "blocked: drive upload parent must be an approved Olivaw folder" >&2
      exit 10
    fi
    block_if_arg "--replace" "$@"
    ;;
  drive:mkdir|drive:copy|drive:move|drive:rename|drive:delete|drive:rm|drive:del|drive:share|drive:unshare)
    echo "blocked: drive ${command_name} is not an approved Olivaw runtime operation" >&2
    exit 10
    ;;
  drive:permissions)
    # Read-only permission listing is allowed for verification.
    ;;
  docs:create)
    parent_id="$(arg_value "--parent" "$@" || true)"
    if ! folder_allowed "${parent_id}"; then
      echo "blocked: docs create parent must be an approved Olivaw folder" >&2
      exit 10
    fi
    ;;
  docs:write)
    doc_id="${3:-}"
    if ! drive_file_in_allowed_folder "${doc_id}"; then
      echo "blocked: docs write target must live in an approved Olivaw folder" >&2
      exit 10
    fi
    ;;
  docs:copy|docs:delete|docs:clear|docs:sed|docs:format|docs:insert|docs:update|docs:edit|docs:find-replace|docs:add-tab|docs:rename-tab|docs:delete-tab)
    echo "blocked: docs ${command_name} is not in the approved write surface; use docs create/write only" >&2
    exit 10
    ;;
  sheets:create)
    parent_id="$(arg_value "--parent" "$@" || true)"
    if ! folder_allowed "${parent_id}"; then
      echo "blocked: sheets create parent must be an approved Olivaw folder" >&2
      exit 10
    fi
    ;;
  sheets:add-tab)
    spreadsheet_id="${3:-}"
    tab_name="${4:-}"
    if [[ "${spreadsheet_id}" != "${OLIVAW_TRACKER_SHEET_ID}" ]] || ! tab_allowed "${tab_name}"; then
      echo "blocked: sheets add-tab is allowed only for approved Olivaw tracker tabs" >&2
      exit 10
    fi
    ;;
  sheets:update|sheets:append)
    spreadsheet_id="${3:-}"
    sheet_range="${4:-}"
    tab_name="$(range_tab "${sheet_range}")"
    if [[ "${spreadsheet_id}" != "${OLIVAW_TRACKER_SHEET_ID}" ]] || ! tab_allowed "${tab_name}"; then
      echo "blocked: sheets ${command_name} is allowed only for approved Olivaw tracker tabs" >&2
      exit 10
    fi
    ;;
  sheets:clear|sheets:delete-tab|sheets:copy|sheets:insert|sheets:merge|sheets:unmerge|sheets:find-replace)
    echo "blocked: sheets ${command_name} is not an approved Olivaw operation" >&2
    exit 10
    ;;
  gmail:labels)
    subcommand="${3:-}"
    case "${subcommand}" in
      list|ls|get|info|show)
        ;;
      create|add|new)
        label_name="${4:-}"
        if [[ "${label_name}" != Olivaw/* ]]; then
          echo "blocked: Gmail label creation is restricted to Olivaw/*" >&2
          exit 10
        fi
        ;;
      *)
        echo "blocked: Gmail labels ${subcommand} is not approved" >&2
        exit 10
        ;;
    esac
    ;;
  gmail:drafts)
    subcommand="${3:-}"
    case "${subcommand}" in
      list|ls|get|info|show)
        ;;
      create|add|new|update|edit|set)
        subject="$(arg_value "--subject" "$@" || true)"
        if ! subject_has_olivaw_prefix "${subject}"; then
          echo "blocked: Gmail draft subject must start with [Olivaw" >&2
          exit 10
        fi
        ;;
      send|post|delete|rm|del|remove)
        echo "blocked: Gmail draft ${subcommand} is not approved" >&2
        exit 10
        ;;
      *)
        echo "blocked: Gmail drafts ${subcommand} is not approved" >&2
        exit 10
        ;;
    esac
    ;;
  gmail:send|gmail:forward|gmail:fwd|gmail:autoreply|gmail:trash|gmail:archive|gmail:batch|gmail:settings)
    echo "blocked: Gmail ${command_name} is outside the approved draft-only surface" >&2
    exit 10
    ;;
  calendar:create)
    calendar_id="${3:-}"
    summary="$(arg_value "--summary" "$@" || true)"
    [[ "${calendar_id}" == "${OLIVAW_CALENDAR_ID}" ]] || {
      echo "blocked: calendar create is restricted to the approved Olivaw calendar id" >&2
      exit 10
    }
    event_summary_allowed "${summary}" || {
      echo "blocked: calendar summary must start with [Olivaw ...]" >&2
      exit 10
    }
    ensure_no_external_calendar_effects "$@"
    if ! has_arg "--send-updates" "$@"; then
      set -- "$@" "--send-updates=none"
    fi
    if ! has_arg "--private-prop" "$@"; then
      set -- "$@" "--private-prop=olivaw_managed=true"
    fi
    ;;
  calendar:update)
    calendar_id="${3:-}"
    event_id="${4:-}"
    [[ "${calendar_id}" == "${OLIVAW_CALENDAR_ID}" ]] || {
      echo "blocked: calendar update is restricted to the approved Olivaw calendar id" >&2
      exit 10
    }
    ensure_no_external_calendar_effects "$@"
    if ! calendar_event_is_olivaw_owned "${calendar_id}" "${event_id}"; then
      echo "blocked: calendar update target is not Olivaw-owned" >&2
      exit 10
    fi
    if has_arg "--summary" "$@"; then
      summary="$(arg_value "--summary" "$@" || true)"
      event_summary_allowed "${summary}" || {
        echo "blocked: calendar summary must start with [Olivaw ...]" >&2
        exit 10
      }
    fi
    if ! has_arg "--send-updates" "$@"; then
      set -- "$@" "--send-updates=none"
    fi
    ;;
  calendar:delete|calendar:move|calendar:respond|calendar:subscribe|calendar:create-calendar|calendar:acl)
    echo "blocked: calendar ${command_name} is outside the approved internal-event surface" >&2
    exit 10
    ;;
  *)
    echo "blocked: olivaw gog policy does not allow '${family} ${command_name}'" >&2
    exit 10
    ;;
esac

export GOG_ACCOUNT="${ACCOUNT_DEFAULT}"
exec "${gog_base[@]}" "$@"
