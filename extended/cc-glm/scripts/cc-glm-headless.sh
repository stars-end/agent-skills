#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
cc-glm-headless.sh

Run cc-glm (a zsh function) in headless mode without fighting shell quoting.

Usage:
  cc-glm-headless.sh --prompt "..."
  cc-glm-headless.sh --prompt-file /path/to/prompt.txt
  echo "..." | cc-glm-headless.sh

Notes:
  - Prefers: zsh -ic 'cc-glm ...'
  - Fallback: claude -p ...
  - Avoid passing secrets; do not print dotfiles/configs.
EOF
}

PROMPT="${PROMPT:-}"
PROMPT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      PROMPT="${2:-}"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: --prompt-file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
fi

if [[ -z "${PROMPT}" ]]; then
  # If stdin is a pipe, read it.
  if [[ ! -t 0 ]]; then
    PROMPT="$(cat)"
  fi
fi

if [[ -z "${PROMPT}" ]]; then
  echo "Error: missing prompt (use --prompt, --prompt-file, or stdin)" >&2
  exit 1
fi

tmp="$(mktemp)"
cleanup() { rm -f "$tmp" 2>/dev/null || true; }
trap cleanup EXIT
printf "%s" "$PROMPT" > "$tmp"

resolve_glm_auth_token() {
  # Resolution precedence:
  # 1) CC_GLM_AUTH_TOKEN (plain token)
  # 2) ZAI_API_KEY (plain token or op:// reference)
  # 3) CC_GLM_OP_URI (op:// reference)
  # 4) default op:// reference: op://dev/Agent-Secrets-Production/ZAI_API_KEY
  #
  # Never echo secrets in error paths.
  if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
    printf "%s" "$CC_GLM_AUTH_TOKEN"
    return 0
  fi

  local ref=""
  if [[ -n "${ZAI_API_KEY:-}" ]]; then
    ref="$ZAI_API_KEY"
  elif [[ -n "${CC_GLM_OP_URI:-}" ]]; then
    ref="$CC_GLM_OP_URI"
  else
    ref="op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY"
  fi

  if [[ "$ref" == op://* ]]; then
    if ! command -v op >/dev/null 2>&1; then
      return 1
    fi

    # If op isn't already authenticated, allow the standard DX pattern:
    # auto-load OP_SERVICE_ACCOUNT_TOKEN from the protected token file created by:
    #   ~/agent-skills/scripts/create-op-credential.sh
    if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
      host="$(hostname)"
      token_file="${OP_SERVICE_ACCOUNT_TOKEN_FILE:-$HOME/.config/systemd/user/op-${host}-token}"
      legacy_file="$HOME/.config/systemd/user/op-macmini-token"
      if [[ -f "$token_file" ]]; then
        OP_SERVICE_ACCOUNT_TOKEN="$(cat "$token_file" 2>/dev/null || true)"
        export OP_SERVICE_ACCOUNT_TOKEN
      elif [[ -f "$legacy_file" ]]; then
        OP_SERVICE_ACCOUNT_TOKEN="$(cat "$legacy_file" 2>/dev/null || true)"
        export OP_SERVICE_ACCOUNT_TOKEN
      fi
    fi

    op read "$ref" 2>/dev/null
    return $?
  fi

  printf "%s" "$ref"
  return 0
}

# Prefer direct env-based invocation (more deterministic; avoids shell init noise).
# Set CC_GLM_AUTH_TOKEN (required) and optionally:
#   CC_GLM_BASE_URL, CC_GLM_MODEL, CC_GLM_TIMEOUT_MS
if command -v claude >/dev/null 2>&1; then
  token="$(resolve_glm_auth_token || true)"
  if [[ -n "${token:-}" ]]; then
    ANTHROPIC_AUTH_TOKEN="$token" \
  ANTHROPIC_BASE_URL="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${CC_GLM_MODEL:-glm-4.7}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${CC_GLM_MODEL:-glm-4.7}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${CC_GLM_MODEL:-glm-4.7}" \
  API_TIMEOUT_MS="${CC_GLM_TIMEOUT_MS:-3000000}" \
  claude --dangerously-skip-permissions --model "${CC_GLM_MODEL:-glm-4.7}" -p "$(cat "$tmp")" --output-format text
    exit 0
  fi
fi

# Prefer cc-glm (zsh function). Use a temp file to avoid quoting issues.
#
# NOTE: This path loads your shell init files and may be noisy or brittle. Prefer setting
# ZAI_API_KEY as an op:// reference (or CC_GLM_AUTH_TOKEN) so the deterministic path above runs.
if zsh -ic "cc-glm -p \"\$(cat '$tmp')\" --output-format text"; then
  # cc-glm printed output already.
  exit 0
fi

# Fallback: standard Claude Code headless mode.
if command -v claude >/dev/null 2>&1; then
  claude -p "$(cat "$tmp")" --output-format text
  exit 0
fi

echo "Error: neither cc-glm nor claude is available on PATH" >&2
exit 1
