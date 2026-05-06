#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_DEFAULT="fengning@stars-end.ai"
CLIENT_DEFAULT="olivaw-gog"
STATE_FILE_DEFAULT="${HOME}/.hermes/profiles/olivaw/google-ops-state.env"

ACCOUNT="${GOG_ACCOUNT:-${ACCOUNT_DEFAULT}}"
CLIENT="${GOG_CLIENT:-${CLIENT_DEFAULT}}"
STATE_FILE="${OLIVAW_GOOGLE_STATE:-${STATE_FILE_DEFAULT}}"

gog_base=(gog --client "${CLIENT}" --account "${ACCOUNT}" --gmail-no-send --no-input)

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "blocked: missing required command: $1" >&2
    exit 127
  }
}

json_id() {
  jq -r '
    .id
    // .file.id
    // .folder.id
    // .documentId
    // .document.documentId
    // .spreadsheetId
    // .spreadsheet.spreadsheetId
    // .draftId
    // .draft.id
    // .message.id
    // .event.id
    // empty
  '
}

drive_find_folder() {
  local name="$1"
  local parent="${2:-}"
  local query="name = '${name}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
  if [[ -n "${parent}" ]]; then
    query="${query} and '${parent}' in parents"
  fi
  "${gog_base[@]}" drive search "${query}" --raw-query --json --max 10 \
    | jq -r '.files[0].id // empty'
}

drive_mkdir_once() {
  local name="$1"
  local parent="${2:-}"
  local existing
  existing="$(drive_find_folder "${name}" "${parent}")"
  if [[ -n "${existing}" ]]; then
    printf '%s\n' "${existing}"
    return 0
  fi
  if [[ -n "${parent}" ]]; then
    "${gog_base[@]}" drive mkdir "${name}" --parent "${parent}" --json | json_id
  else
    "${gog_base[@]}" drive mkdir "${name}" --json | json_id
  fi
}

drive_find_file() {
  local name="$1"
  local mime="$2"
  local parent="$3"
  local query="name = '${name}' and mimeType = '${mime}' and trashed = false and '${parent}' in parents"
  "${gog_base[@]}" drive search "${query}" --raw-query --json --max 10 \
    | jq -r '.files[0].id // empty'
}

create_tracker_once() {
  local title="Olivaw Ops Tracker"
  local parent="$1"
  local existing
  existing="$(drive_find_file "${title}" "application/vnd.google-apps.spreadsheet" "${parent}")"
  if [[ -n "${existing}" ]]; then
    printf '%s\n' "${existing}"
    return 0
  fi
  "${gog_base[@]}" sheets create "${title}" \
    --parent "${parent}" \
    --sheets "Intake,Approvals,Artifacts,Reservations,Finance Admin,Healthcare Admin,Calendar Holds,Audit" \
    --json | json_id
}

ensure_tracker_tab() {
  local sheet_id="$1"
  local tab="$2"
  if "${gog_base[@]}" sheets metadata "${sheet_id}" --json \
    | jq -e --arg tab "${tab}" '.sheets[]? | select(.properties.title == $tab)' >/dev/null; then
    return 0
  fi
  "${gog_base[@]}" sheets add-tab "${sheet_id}" "${tab}" --json >/dev/null
}

ensure_tracker_tabs() {
  local sheet_id="$1"
  local tab
  for tab in \
    "Intake" \
    "Approvals" \
    "Artifacts" \
    "Reservations" \
    "Finance Admin" \
    "Healthcare Admin" \
    "Calendar Holds" \
    "Audit"; do
    ensure_tracker_tab "${sheet_id}" "${tab}"
  done
}

ensure_label() {
  local label="$1"
  if "${gog_base[@]}" gmail labels list --json | jq -e --arg label "${label}" '.labels[]? | select(.name == $label)' >/dev/null; then
    return 0
  fi
  "${gog_base[@]}" gmail labels create "${label}" --json >/dev/null
}

update_headers() {
  local sheet_id="$1"
  "${gog_base[@]}" sheets update "${sheet_id}" "'Intake'!A1:J1" \
    --values-json '[["request_id","created_at","source","surface","summary","sensitivity","status","owner","artifact_url","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Approvals'!A1:J1" \
    --values-json '[["approval_id","created_at","request_id","proposed_action","risk_level","approved_by","approval_status","approved_at","expires_at","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Artifacts'!A1:J1" \
    --values-json '[["artifact_id","created_at","type","title","drive_url","folder","sensitivity","source_request_id","created_by","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Reservations'!A1:J1" \
    --values-json '[["request_id","created_at","venue","date_time","party_size","status","calendar_event_url","draft_url","approval_status","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Finance Admin'!A1:J1" \
    --values-json '[["item_id","created_at","vendor","amount","due_date","status","artifact_url","sensitivity","next_action","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Healthcare Admin'!A1:J1" \
    --values-json '[["item_id","created_at","provider","service_date","amount","status","artifact_url","sensitivity","next_action","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Calendar Holds'!A1:J1" \
    --values-json '[["event_id","created_at","title","start","end","status","calendar_url","source_request_id","approval_status","notes"]]' --json >/dev/null
  "${gog_base[@]}" sheets update "${sheet_id}" "'Audit'!A1:K1" \
    --values-json '[["timestamp","correlation_id","command_family","action","target","sensitivity","approval_status","result","artifact_url","blocked_reason","notes"]]' --json >/dev/null
}

write_state() {
  local root="$1"
  local inbox="$2"
  local drafts="$3"
  local working="$4"
  local finance="$5"
  local healthcare="$6"
  local reservations="$7"
  local archive="$8"
  local audit="$9"
  local tracker="${10}"
  local state_dir
  local tmp
  state_dir="$(dirname "${STATE_FILE}")"
  mkdir -p "${state_dir}"
  tmp="$(mktemp "${state_dir}/google-ops-state.XXXXXX")"
  {
    printf '# Olivaw Google Ops state. Generated by olivaw-google-ops-bootstrap.sh.\n'
    printf 'OLIVAW_GOOGLE_ACCOUNT=%q\n' "${ACCOUNT}"
    printf 'OLIVAW_GOG_CLIENT=%q\n' "${CLIENT}"
    printf 'OLIVAW_CALENDAR_ID=%q\n' "${ACCOUNT}"
    printf 'OLIVAW_OPS_ROOT_ID=%q\n' "${root}"
    printf 'OLIVAW_INBOX_DROP_ID=%q\n' "${inbox}"
    printf 'OLIVAW_DRAFTS_REVIEW_ID=%q\n' "${drafts}"
    printf 'OLIVAW_APPROVED_WORKING_ID=%q\n' "${working}"
    printf 'OLIVAW_FINANCE_ADMIN_ID=%q\n' "${finance}"
    printf 'OLIVAW_HEALTHCARE_ADMIN_ID=%q\n' "${healthcare}"
    printf 'OLIVAW_RESERVATIONS_ID=%q\n' "${reservations}"
    printf 'OLIVAW_ARCHIVE_ID=%q\n' "${archive}"
    printf 'OLIVAW_AUDIT_LOGS_ID=%q\n' "${audit}"
    printf 'OLIVAW_TRACKER_SHEET_ID=%q\n' "${tracker}"
    printf 'OLIVAW_ALLOWED_FOLDER_IDS=%q\n' "${root},${inbox},${drafts},${working},${finance},${healthcare},${reservations},${archive},${audit}"
    printf 'OLIVAW_TRACKER_TABS=%q\n' "Intake,Approvals,Artifacts,Reservations,Finance Admin,Healthcare Admin,Calendar Holds,Audit"
  } >"${tmp}"
  chmod 0600 "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

need gog
need jq

"${gog_base[@]}" auth doctor --check --json >/dev/null

root="$(drive_mkdir_once "Olivaw Ops")"
inbox="$(drive_mkdir_once "00 Inbox Drop" "${root}")"
drafts="$(drive_mkdir_once "01 Drafts For Review" "${root}")"
working="$(drive_mkdir_once "02 Approved Working Files" "${root}")"
finance="$(drive_mkdir_once "03 Finance Admin" "${root}")"
healthcare="$(drive_mkdir_once "04 Healthcare Admin" "${root}")"
reservations="$(drive_mkdir_once "05 Reservations" "${root}")"
archive="$(drive_mkdir_once "90 Archive" "${root}")"
audit="$(drive_mkdir_once "99 Audit Logs" "${root}")"

tracker="$(create_tracker_once "${working}")"
ensure_tracker_tabs "${tracker}"
update_headers "${tracker}"
write_state "${root}" "${inbox}" "${drafts}" "${working}" "${finance}" "${healthcare}" "${reservations}" "${archive}" "${audit}" "${tracker}"

for label in \
  "Olivaw/Inbox" \
  "Olivaw/Needs Review" \
  "Olivaw/Draft Created" \
  "Olivaw/Waiting On Fengning" \
  "Olivaw/Waiting On External" \
  "Olivaw/Done" \
  "Olivaw/Finance" \
  "Olivaw/Healthcare" \
  "Olivaw/Reservations" \
  "Olivaw/Startup Ops"; do
  if [[ "${OLIVAW_SKIP_GMAIL_SETUP:-0}" == "1" ]]; then
    break
  fi
  ensure_label "${label}"
done

jq -n \
  --arg account "${ACCOUNT}" \
  --arg state_file "${STATE_FILE}" \
  --arg ops_root_id "${root}" \
  --arg inbox_drop_id "${inbox}" \
  --arg drafts_review_id "${drafts}" \
  --arg approved_working_id "${working}" \
  --arg finance_admin_id "${finance}" \
  --arg healthcare_admin_id "${healthcare}" \
  --arg reservations_id "${reservations}" \
  --arg archive_id "${archive}" \
  --arg audit_logs_id "${audit}" \
  --arg tracker_sheet_id "${tracker}" \
  --arg calendar_id "${ACCOUNT}" \
  '{
    ok: true,
    account: $account,
    state_file: $state_file,
    drive: {
      ops_root_id: $ops_root_id,
      inbox_drop_id: $inbox_drop_id,
      drafts_review_id: $drafts_review_id,
      approved_working_id: $approved_working_id,
      finance_admin_id: $finance_admin_id,
      healthcare_admin_id: $healthcare_admin_id,
      reservations_id: $reservations_id,
      archive_id: $archive_id,
      audit_logs_id: $audit_logs_id
    },
    tracker_sheet_id: $tracker_sheet_id,
    calendar_id: $calendar_id
  }'
