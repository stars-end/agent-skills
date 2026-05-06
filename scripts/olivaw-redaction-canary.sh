#!/usr/bin/env bash
set -euo pipefail

sample='synthetic sk-test-REDACT_ME xoxb-REDACT_ME code=FAKE_CODE state=FAKE_STATE acct=123456789 claim=CLM-FAKE-001'

sanitize() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]+/[REDACTED_SECRET]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9_-]+/[REDACTED_SLACK_TOKEN]/g' \
    -e 's/(code=)[^&[:space:]]+/\1[REDACTED_OAUTH_CODE]/g' \
    -e 's/(state=)[^&[:space:]]+/\1[REDACTED_OAUTH_STATE]/g' \
    -e 's/(acct=)[0-9]+/\1[REDACTED_ACCOUNT]/g' \
    -e 's/(claim=)[A-Za-z0-9_-]+/\1[REDACTED_CLAIM]/g'
}

sanitized="$(printf '%s' "${sample}" | sanitize)"

leak=false
for needle in 'sk-test-REDACT_ME' 'xoxb-REDACT_ME' 'FAKE_CODE' 'FAKE_STATE' '123456789' 'CLM-FAKE-001'; do
  if [[ "${sanitized}" == *"${needle}"* ]]; then
    leak=true
  fi
done

cat <<JSON
{
  "ok": $([[ "${leak}" == false ]] && echo true || echo false),
  "canary": "synthetic-only",
  "redaction_markers": [
    "REDACTED_SECRET",
    "REDACTED_SLACK_TOKEN",
    "REDACTED_OAUTH_CODE",
    "REDACTED_OAUTH_STATE",
    "REDACTED_ACCOUNT",
    "REDACTED_CLAIM"
  ],
  "sanitized_preview": "$(printf '%s' "${sanitized}")"
}
JSON

if [[ "${leak}" == true ]]; then
  exit 1
fi
