#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: olivaw-slack-thread-evidence.sh --channel <id> --contains <text> --expect-reply <text>

Read-only Slack evidence helper for Olivaw manual canaries. It resolves the
Olivaw bot token from the agent-safe 1Password cache, finds the latest matching
top-level message in a channel, reads its thread, and emits sanitized JSON.
EOF
}

channel=""
contains=""
expect_reply=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      channel="${2:-}"
      shift 2
      ;;
    --contains)
      contains="${2:-}"
      shift 2
      ;;
    --expect-reply)
      expect_reply="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${channel}" || -z "${contains}" || -z "${expect_reply}" ]]; then
  usage
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/dx-auth.sh
source "${repo_root}/scripts/lib/dx-auth.sh"

token="$(
  DX_AUTH_CACHE_ONLY=1 dx_auth_read_secret_cached \
    'op://dev/Agent-Secrets-Production/SLACK_STARS_END_OLIVAW_BOT_TOKEN' \
    'slack_stars_end_olivaw_bot_token'
)"

if [[ -z "${token}" ]]; then
  echo "blocked: Olivaw Slack token unavailable from agent-safe cache" >&2
  exit 1
fi

history_json="$(
  curl -sS \
    -H "Authorization: Bearer ${token}" \
    "https://slack.com/api/conversations.history?channel=${channel}&limit=50"
)"

ts="$(
  printf '%s' "${history_json}" |
    jq -r --arg needle "${contains}" '.messages[]? | select(.text | contains($needle)) | .ts' |
    head -n1
)"

if [[ -z "${ts}" ]]; then
  printf '%s\n' "${history_json}" |
    jq --arg channel "${channel}" --arg needle "${contains}" '{
      ok: false,
      channel: $channel,
      reason: "matching_parent_not_found",
      contains: $needle,
      slack_ok: .ok,
      slack_error: .error
    }'
  exit 1
fi

replies_json="$(
  curl -sS \
    -H "Authorization: Bearer ${token}" \
    "https://slack.com/api/conversations.replies?channel=${channel}&ts=${ts}&limit=20"
)"

printf '%s\n' "${replies_json}" |
  jq \
    --arg channel "${channel}" \
    --arg thread_ts "${ts}" \
    --arg contains "${contains}" \
    --arg expect_reply "${expect_reply}" '
      def redact:
        gsub("xox[baprs]-[A-Za-z0-9._-]+"; "[REDACTED_SLACK_TOKEN]")
        | gsub("sk-[A-Za-z0-9._-]+"; "[REDACTED_SECRET]")
        | gsub("([?&]code=)[^&[:space:]]+"; "\\1[REDACTED_OAUTH_CODE]")
        | gsub("([?&]state=)[^&[:space:]]+"; "\\1[REDACTED_OAUTH_STATE]");

      {
        ok: (.ok == true and any(.messages[]?; (.text // "") | contains($expect_reply))),
        slack_ok: .ok,
        slack_error: .error,
        channel: $channel,
        parent_contains: $contains,
        thread_ts: $thread_ts,
        expected_reply: $expect_reply,
        reply_found: any(.messages[]?; (.text // "") | contains($expect_reply)),
        message_count: ((.messages // []) | length),
        messages: [
          .messages[]? | {
            ts,
            user,
            bot_id,
            app_id,
            text: ((.text // "") | redact)
          }
        ]
      }
    '
