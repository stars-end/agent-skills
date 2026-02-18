#!/usr/bin/env bash
set -euo pipefail

# cc-glm-headless.sh
#
# Run cc-glm in headless mode with deterministic auth resolution.
# Auth resolution is strict by default - use CC_GLM_ALLOW_FALLBACK=1 to enable
# legacy zsh/cc-glm path when token resolution fails.
#
# DEFAULT REMOTE TARGET POLICY (V2.1):
#   When running headless without explicit host specification, epyc12 is the
#   default target for auth token resolution. The OP_SERVICE_ACCOUNT_TOKEN
#   discovery order is:
#     1) OP_SERVICE_ACCOUNT_TOKEN_FILE (explicit override)
#     2) /home/fengning/.config/systemd/user/op-epyc12-token (canonical epyc12 path)
#     3) $HOME/.config/systemd/user/op-$(hostname)-token (hostname-based)
#     4) $HOME/.config/systemd/user/op-macmini-token (legacy fallback)
#
# Auth resolution precedence (deterministic):
#   1) CC_GLM_AUTH_TOKEN (plain token - highest priority)
#   2) ZAI_API_KEY (plain token OR op:// reference resolved via op CLI)
#   3) CC_GLM_OP_URI (op:// reference)
#   4) Default op:// fallback: op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY
#
# Environment variables:
#   CC_GLM_ALLOW_FALLBACK=1  - Allow fallback to zsh/cc-glm path on auth failure
#   CC_GLM_AUTH_TOKEN        - Direct auth token (bypasses all resolution)
#   ZAI_API_KEY              - Token or op:// reference
#   CC_GLM_OP_URI            - op:// reference for token
#   CC_GLM_OP_VAULT          - 1Password vault name (default: dev)
#   CC_GLM_BASE_URL          - API base URL (default: https://api.z.ai/api/anthropic)
#   CC_GLM_MODEL             - Model name (default: glm-5)
#   CC_GLM_TIMEOUT_MS        - API timeout in ms (default: 3000000)
#   CC_GLM_STRICT_AUTH=0     - Set to 0 to suppress strict auth errors (not recommended)

# Version for debugging/logging
CC_GLM_HEADLESS_VERSION="2.1.1"

usage() {
  cat >&2 <<'EOF'
cc-glm-headless.sh (V2.1 - Deterministic Auth with epyc12 Default)

Run cc-glm in headless mode with deterministic auth resolution.

Usage:
  cc-glm-headless.sh --prompt "..."
  cc-glm-headless.sh --prompt-file /path/to/prompt.txt
  echo "..." | cc-glm-headless.sh

Default Remote Target: epyc12
  When no explicit host is specified, auth token discovery prioritizes:
    1. OP_SERVICE_ACCOUNT_TOKEN_FILE (if set)
    2. /home/fengning/.config/systemd/user/op-epyc12-token (canonical)
    3. $HOME/.config/systemd/user/op-$(hostname)-token (hostname-based)
    4. $HOME/.config/systemd/user/op-macmini-token (legacy)

Auth resolution order (first match wins):
  1. CC_GLM_AUTH_TOKEN env (plain token)
  2. ZAI_API_KEY env (plain token or op:// reference)
  3. CC_GLM_OP_URI env (op:// reference)
  4. Default: op://dev/Agent-Secrets-Production/ZAI_API_KEY

Options:
  --prompt TEXT       Inline prompt text
  --prompt-file FILE  Read prompt from file
  --version           Show version
  -h, --help          Show this help

Environment:
  CC_GLM_ALLOW_FALLBACK=1   Allow zsh/cc-glm fallback on auth failure
  CC_GLM_STRICT_AUTH=0      Suppress strict auth errors (not recommended)

Examples:
  # Direct token (recommended for CI)
  CC_GLM_AUTH_TOKEN=xxx cc-glm-headless.sh --prompt "task"

  # Using op:// reference in ZAI_API_KEY
  ZAI_API_KEY="op://dev/Vault/item" cc-glm-headless.sh --prompt "task"

  # With fallback allowed (legacy behavior)
  CC_GLM_ALLOW_FALLBACK=1 cc-glm-headless.sh --prompt "task"
EOF
}

# Logging helpers (all output to stderr to keep stdout clean)
log_info() {
  echo "[cc-glm-headless] $*" >&2
}
log_warn() {
  echo "[cc-glm-headless] WARN: $*" >&2
}
log_error() {
  echo "[cc-glm-headless] ERROR: $*" >&2
}
log_debug() {
  if [[ "${CC_GLM_DEBUG:-}" == "1" ]]; then
    echo "[cc-glm-headless] DEBUG: $*" >&2
  fi
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
    --version)
      echo "cc-glm-headless.sh version $CC_GLM_HEADLESS_VERSION"
      exit 0
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
    log_error "--prompt-file not found: $PROMPT_FILE"
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
  log_error "missing prompt (use --prompt, --prompt-file, or stdin)"
  exit 1
fi

tmp="$(mktemp)"
cleanup() { rm -f "$tmp" 2>/dev/null || true; }
trap cleanup EXIT
printf "%s" "$PROMPT" > "$tmp"

# ============================================================================
# AUTH TOKEN RESOLUTION (V2.0 - Deterministic)
# ============================================================================
#
# Resolution precedence (strict, in order):
#   1. CC_GLM_AUTH_TOKEN - direct token, no processing needed
#   2. ZAI_API_KEY - may be plain token OR op:// reference
#   3. CC_GLM_OP_URI - explicit op:// reference
#   4. Default op:// URI constructed from CC_GLM_OP_VAULT
#
# Returns:
#   0 on success, token printed to stdout
#   1 on failure, error message already printed to stderr
#
# Security: Never echoes the token value itself.
# ============================================================================

resolve_glm_auth_token() {
  local source=""  # Track where we found the token for debugging

  # 1) CC_GLM_AUTH_TOKEN - highest priority, direct token
  if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
    log_debug "auth source: CC_GLM_AUTH_TOKEN (direct)"
    printf "%s" "$CC_GLM_AUTH_TOKEN"
    return 0
  fi

  # 2) ZAI_API_KEY - may be plain token or op:// reference
  if [[ -n "${ZAI_API_KEY:-}" ]]; then
    if [[ "$ZAI_API_KEY" == op://* ]]; then
      log_debug "auth source: ZAI_API_KEY (op:// reference)"
      _resolve_op_reference "$ZAI_API_KEY"
      return $?
    else
      log_debug "auth source: ZAI_API_KEY (plain token)"
      printf "%s" "$ZAI_API_KEY"
      return 0
    fi
  fi

  # 3) CC_GLM_OP_URI - explicit op:// reference
  if [[ -n "${CC_GLM_OP_URI:-}" ]]; then
    log_debug "auth source: CC_GLM_OP_URI"
    _resolve_op_reference "$CC_GLM_OP_URI"
    return $?
  fi

  # 4) Default op:// fallback
  local default_uri="op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY"
  log_debug "auth source: default op:// URI ($default_uri)"
  _resolve_op_reference "$default_uri"
  return $?
}

# Resolve an op:// reference using the 1Password CLI.
# Handles OP_SERVICE_ACCOUNT_TOKEN auto-discovery from hostname-based token files.
#
# Arguments:
#   $1 - op:// reference URI
#
# Returns:
#   0 on success, token printed to stdout
#   1 on failure with error message to stderr
_resolve_op_reference() {
  local ref="$1"

  if [[ "$ref" != op://* ]]; then
    log_error "internal error: _resolve_op_reference called with non-op:// reference"
    return 1
  fi

  # Check if op CLI is available
  if ! command -v op >/dev/null 2>&1; then
    log_error "op CLI not found. Install 1Password CLI to use op:// references."
    log_error "  See: https://developer.1password.com/docs/cli/get-started/"
    return 1
  fi

  # Auto-discover OP_SERVICE_ACCOUNT_TOKEN if not set
  # Uses hostname-based token file convention from create-op-credential.sh
  if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    local host token_file epyc12_file legacy_file

    host="$(hostname)"
    token_file="${OP_SERVICE_ACCOUNT_TOKEN_FILE:-$HOME/.config/systemd/user/op-${host}-token}"
    epyc12_file="/home/fengning/.config/systemd/user/op-epyc12-token"
    legacy_file="$HOME/.config/systemd/user/op-macmini-token"

    if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN_FILE:-}" && -f "$token_file" ]]; then
      log_debug "loading OP_SERVICE_ACCOUNT_TOKEN from: $token_file"
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$token_file" 2>/dev/null || true)"
      export OP_SERVICE_ACCOUNT_TOKEN
    elif [[ -f "$epyc12_file" ]]; then
      # Explicit, stable fallback for the canonical epyc12 runtime.
      log_debug "loading OP_SERVICE_ACCOUNT_TOKEN from epyc12 path: $epyc12_file"
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$epyc12_file" 2>/dev/null || true)"
      export OP_SERVICE_ACCOUNT_TOKEN
    elif [[ -f "$token_file" ]]; then
      log_debug "loading OP_SERVICE_ACCOUNT_TOKEN from host path: $token_file"
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$token_file" 2>/dev/null || true)"
      export OP_SERVICE_ACCOUNT_TOKEN
    elif [[ -f "$legacy_file" ]]; then
      log_debug "loading OP_SERVICE_ACCOUNT_TOKEN from legacy: $legacy_file"
      OP_SERVICE_ACCOUNT_TOKEN="$(cat "$legacy_file" 2>/dev/null || true)"
      export OP_SERVICE_ACCOUNT_TOKEN
    fi
  fi

  # Attempt to read from 1Password
  # Redirect stderr to suppress op's verbose error messages
  local token
  if ! token="$(op read "$ref" 2>/dev/null)"; then
    _print_op_resolution_error "$ref"
    return 1
  fi

  # Validate we got something
  if [[ -z "$token" ]]; then
    log_error "op read returned empty value for: $ref"
    log_error "  The secret may be empty or you may not have access."
    return 1
  fi

  printf "%s" "$token"
  return 0
}

# Print actionable error message when op:// resolution fails.
# Never reveals secret values.
_print_op_resolution_error() {
  local ref="$1"

  log_error "Failed to resolve op:// reference."
  log_error ""
  log_error "Resolution path attempted: $ref"
  log_error ""
  log_error "Possible causes:"
  log_error "  1. OP_SERVICE_ACCOUNT_TOKEN not set or expired"
  log_error "  2. Token file not found at expected location"
  log_error "  3. 1Password CLI (op) not authenticated"
  log_error "  4. Service account lacks access to specified vault/item"
  log_error ""
  log_error "Remediation:"
  log_error "  - For remote hosts: Run ~/agent-skills/scripts/create-op-credential.sh"
  log_error "  - For local dev: Ensure 'op signin' has been run"
  log_error "  - For CI: Set OP_SERVICE_ACCOUNT_TOKEN directly"
  log_error "  - Alternative: Set CC_GLM_AUTH_TOKEN or ZAI_API_KEY directly"
  log_error ""
  log_error "To bypass this error (not recommended): CC_GLM_ALLOW_FALLBACK=1"
}

# ============================================================================
# MAIN EXECUTION PATHS
# ============================================================================

# Check if claude binary is available
if ! command -v claude >/dev/null 2>&1; then
  log_error "claude CLI not found on PATH"
  log_error "  Install: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# Resolve auth token
token=""
token_source=""

# Try to resolve token
if [[ -n "${CC_GLM_AUTH_TOKEN:-}" ]]; then
  token="$CC_GLM_AUTH_TOKEN"
  token_source="CC_GLM_AUTH_TOKEN"
elif [[ -n "${ZAI_API_KEY:-}" ]]; then
  if [[ "$ZAI_API_KEY" == op://* ]]; then
    if token="$(_resolve_op_reference "$ZAI_API_KEY" 2>/dev/null)"; then
      token_source="ZAI_API_KEY (op://)"
    fi
  else
    token="$ZAI_API_KEY"
    token_source="ZAI_API_KEY"
  fi
elif [[ -n "${CC_GLM_OP_URI:-}" ]]; then
  if token="$(_resolve_op_reference "$CC_GLM_OP_URI" 2>/dev/null)"; then
    token_source="CC_GLM_OP_URI"
  fi
else
  # Try default op:// fallback
  default_uri="op://${CC_GLM_OP_VAULT:-dev}/Agent-Secrets-Production/ZAI_API_KEY"
  if token="$(_resolve_op_reference "$default_uri" 2>/dev/null)"; then
    token_source="default op://"
  fi
fi

# Handle token resolution failure
if [[ -z "${token:-}" ]]; then
  if [[ "${CC_GLM_ALLOW_FALLBACK:-}" == "1" ]]; then
    log_warn "Token resolution failed, but CC_GLM_ALLOW_FALLBACK=1 - attempting zsh/cc-glm path"
    log_warn "This path is non-deterministic and may break parallel jobs"

    # Attempt zsh/cc-glm fallback
    if zsh -ic "cc-glm -p \"\$(cat '$tmp')\" --output-format text" 2>/dev/null; then
      exit 0
    fi

    # Final fallback: standard claude
    log_warn "zsh/cc-glm path failed, attempting standard claude (will likely fail without auth)"
    claude -p "$(cat "$tmp")" --output-format text
    exit $?
  fi

  # Strict mode: fail with actionable error
  if [[ "${CC_GLM_STRICT_AUTH:-1}" != "0" ]]; then
    log_error ""
    log_error "=========================================="
    log_error "AUTH TOKEN RESOLUTION FAILED"
    log_error "=========================================="
    log_error ""
    log_error "No auth token could be resolved from:"
    log_error "  1. CC_GLM_AUTH_TOKEN (not set)"
    log_error "  2. ZAI_API_KEY (not set or op:// resolution failed)"
    log_error "  3. CC_GLM_OP_URI (not set or op:// resolution failed)"
    log_error "  4. Default op:// fallback (resolution failed)"
    log_error ""
    log_error "Required action: Set one of these environment variables:"
    log_error ""
    log_error "  Option A (recommended for CI/remote):"
    log_error "    export CC_GLM_AUTH_TOKEN='your-token-here'"
    log_error ""
    log_error "  Option B (with 1Password CLI):"
    log_error "    export ZAI_API_KEY='your-token-or-op://reference'"
    log_error ""
    log_error "  Option C (explicit op:// reference):"
    log_error "    export CC_GLM_OP_URI='op://vault/item/field'"
    log_error ""
    log_error "For remote hosts, ensure OP_SERVICE_ACCOUNT_TOKEN is available:"
    log_error "  ~/agent-skills/scripts/create-op-credential.sh"
    log_error ""
    log_error "To allow fallback (not recommended for parallel jobs):"
    log_error "  CC_GLM_ALLOW_FALLBACK=1 cc-glm-headless.sh ..."
    log_error ""
    exit 10  # Exit code 10 = auth resolution failure
  fi

  # Non-strict mode: try zsh/cc-glm path but warn
  log_warn "Proceeding without resolved token (CC_GLM_STRICT_AUTH=0)"
  if zsh -ic "cc-glm -p \"\$(cat '$tmp')\" --output-format text" 2>/dev/null; then
    exit 0
  fi
  claude -p "$(cat "$tmp")" --output-format text
  exit $?
fi

# Success: we have a resolved token
log_debug "auth resolved successfully from: $token_source"

# Run claude with resolved auth
ANTHROPIC_AUTH_TOKEN="$token" \
ANTHROPIC_API_KEY="$token" \
ANTHROPIC_BASE_URL="${CC_GLM_BASE_URL:-https://api.z.ai/api/anthropic}" \
ANTHROPIC_DEFAULT_OPUS_MODEL="${CC_GLM_MODEL:-glm-5}" \
ANTHROPIC_DEFAULT_SONNET_MODEL="${CC_GLM_MODEL:-glm-5}" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="${CC_GLM_MODEL:-glm-5}" \
API_TIMEOUT_MS="${CC_GLM_TIMEOUT_MS:-3000000}" \
claude --dangerously-skip-permissions --model "${CC_GLM_MODEL:-glm-5}" -p "$(cat "$tmp")" --output-format text
exit $?
