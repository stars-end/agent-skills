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

# Prefer direct env-based invocation (more deterministic; avoids shell init noise).
# Set CC_GLM_AUTH_TOKEN (required) and optionally:
#   CC_GLM_BASE_URL, CC_GLM_MODEL, CC_GLM_TIMEOUT_MS
if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]] && command -v claude >/dev/null 2>&1; then
  ANTHROPIC_AUTH_TOKEN="$CC_GLM_AUTH_TOKEN" \
  ANTHROPIC_BASE_URL="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="${CC_GLM_MODEL:-glm-4.7}" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="${CC_GLM_MODEL:-glm-4.7}" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="${CC_GLM_MODEL:-glm-4.7}" \
  API_TIMEOUT_MS="${CC_GLM_TIMEOUT_MS:-3000000}" \
  claude --dangerously-skip-permissions --model "${CC_GLM_MODEL:-glm-4.7}" -p "$(cat "$tmp")" --output-format text
  exit 0
fi

# Prefer cc-glm (zsh function). Use a temp file to avoid quoting issues.
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
