#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE="${OLIVAW_GOG_SAFE:-${SCRIPT_DIR}/olivaw-gog-safe.sh}"
STATE_FILE="${OLIVAW_GOOGLE_STATE:-${HOME}/.hermes/profiles/olivaw/google-ops-state.env}"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "blocked: missing Olivaw Google state (${STATE_FILE}); run olivaw-google-ops-bootstrap.sh" >&2
  exit 10
fi

# shellcheck disable=SC1090
source "${STATE_FILE}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "blocked: missing required command: $1" >&2
    exit 127
  }
}

json_id() {
  jq -r '
    .id
    // .documentId
    // .document.documentId
    // .file.id
    // .folder.id
    // .draftId
    // .draft.id
    // .message.id
    // .event.id
    // .spreadsheetId
    // .spreadsheet.spreadsheetId
    // empty
  '
}

future_times_json() {
  python3 - <<'PY'
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
tz = ZoneInfo("America/Los_Angeles")
start = datetime.now(tz).replace(hour=9, minute=0, second=0, microsecond=0) + timedelta(days=1)
end = start + timedelta(minutes=30)
print('{"from":"%s","to":"%s"}' % (start.isoformat(), end.isoformat()))
PY
}

run_json() {
  "$@"
}

blocked_expect() {
  local name="$1"
  shift
  local out
  local rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "${rc}" == "10" ]]; then
    jq -n --arg name "${name}" --arg status "pass" --arg output "${out}" '{name:$name,status:$status,output:$output}'
  else
    jq -n --arg name "${name}" --arg status "fail" --argjson rc "${rc}" --arg output "${out}" '{name:$name,status:$status,rc:$rc,output:$output}'
  fi
}

need jq
need python3

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
correlation_id="olivaw-google-canary-${stamp}"
tmp_file="$(mktemp "/tmp/${correlation_id}.XXXXXX.txt")"
trap 'rm -f "${tmp_file}"' EXIT
printf 'Synthetic Olivaw Drive upload canary. Correlation: %s\nNo sensitive payload.\n' "${correlation_id}" >"${tmp_file}"

upload_json="$(run_json "${SAFE}" drive upload "${tmp_file}" --parent "${OLIVAW_AUDIT_LOGS_ID}" --name "${correlation_id}.txt" --json)"
upload_id="$(json_id <<<"${upload_json}")"

doc_json="$(run_json "${SAFE}" docs create "[Olivaw Draft] Synthetic doc canary ${stamp}" --parent "${OLIVAW_DRAFTS_REVIEW_ID}" --json)"
doc_id="$(json_id <<<"${doc_json}")"
run_json "${SAFE}" docs write "${doc_id}" --replace --markdown --text "# Olivaw Synthetic Doc Canary

Correlation: ${correlation_id}

This document is a synthetic internal-write canary. No sensitive payload. External actions: none.
" --json >/dev/null

run_json "${SAFE}" sheets append "${OLIVAW_TRACKER_SHEET_ID}" "'Audit'!A:K" \
  --values-json "[[\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"${correlation_id}\",\"sheets\",\"append\",\"Audit\",\"synthetic\",\"preapproved\",\"allowed\",\"\",\"\",\"synthetic canary row\"]]" \
  --json >/dev/null

draft_json='{}'
draft_id=''
if [[ "${OLIVAW_SKIP_LIVE_GMAIL_DRAFT:-0}" != "1" ]]; then
  draft_json="$(run_json "${SAFE}" gmail drafts create \
    --to "${OLIVAW_GOOGLE_ACCOUNT:-fengning@stars-end.ai}" \
    --subject "[Olivaw Draft] Synthetic draft canary ${stamp}" \
    --body "Synthetic Olivaw draft canary. Correlation: ${correlation_id}. This is a draft only. Do not send." \
    --json)"
  draft_id="$(json_id <<<"${draft_json}")"
fi

times="$(future_times_json)"
from_time="$(jq -r '.from' <<<"${times}")"
to_time="$(jq -r '.to' <<<"${times}")"
event_json="$(run_json "${SAFE}" calendar create "${OLIVAW_CALENDAR_ID}" \
  --summary "[Olivaw Hold] Synthetic calendar canary ${stamp}" \
  --from "${from_time}" \
  --to "${to_time}" \
  --visibility private \
  --transparency free \
  --description "Synthetic Olivaw internal calendar canary. Correlation: ${correlation_id}. External action: none. Guests: none." \
  --reminder popup:10m \
  --json)"
event_id="$(json_id <<<"${event_json}")"

blocked_results="$(
  {
    blocked_expect "gmail_send_blocked" "${SAFE}" gmail send --to "nobody@example.com" --subject "blocked" --body "blocked" --json
    blocked_expect "gmail_draft_send_blocked" "${SAFE}" gmail drafts send "draft-does-not-matter" --json
    blocked_expect "drive_share_blocked" "${SAFE}" drive share "${OLIVAW_OPS_ROOT_ID}" --email "nobody@example.com" --json
    blocked_expect "drive_delete_blocked" "${SAFE}" drive delete "${OLIVAW_OPS_ROOT_ID}" --json
    blocked_expect "drive_upload_outside_folder_blocked" "${SAFE}" drive upload "${tmp_file}" --parent "not-an-approved-folder" --json
    blocked_expect "docs_outside_folder_blocked" "${SAFE}" docs create "[Olivaw Draft] Outside folder blocked" --parent "not-an-approved-folder" --json
    blocked_expect "sheets_wrong_spreadsheet_blocked" "${SAFE}" sheets append "not-the-tracker" "'Audit'!A:K" "blocked" --json
    blocked_expect "calendar_attendees_blocked" "${SAFE}" calendar create "${OLIVAW_CALENDAR_ID}" --summary "[Olivaw Hold] Blocked attendee test" --from "${from_time}" --to "${to_time}" --attendees "nobody@example.com" --json
    blocked_expect "calendar_non_olivaw_summary_blocked" "${SAFE}" calendar create "${OLIVAW_CALENDAR_ID}" --summary "Blocked non-Olivaw event" --from "${from_time}" --to "${to_time}" --json
    blocked_expect "calendar_delete_blocked" "${SAFE}" calendar delete "${OLIVAW_CALENDAR_ID}" "${event_id}" --json
  } | jq -s '.'
)"

blocked_ok="$(jq -e 'all(.[]; .status == "pass")' >/dev/null <<<"${blocked_results}" && printf true || printf false)"

jq -n \
  --arg correlation_id "${correlation_id}" \
  --arg state_file "${STATE_FILE}" \
  --arg upload_id "${upload_id}" \
  --arg doc_id "${doc_id}" \
  --arg draft_id "${draft_id}" \
  --arg event_id "${event_id}" \
  --argjson blocked "${blocked_results}" \
  --argjson blocked_ok "${blocked_ok}" \
  '{
    ok: (($upload_id|length > 0) and ($doc_id|length > 0) and ($event_id|length > 0) and $blocked_ok),
    correlation_id: $correlation_id,
    state_file: $state_file,
    created: {
      drive_upload_id: $upload_id,
      doc_id: $doc_id,
      gmail_draft_id: $draft_id,
      calendar_event_id: $event_id
    },
    blocked_action_tests: $blocked
  }'
