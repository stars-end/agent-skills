#!/usr/bin/env bash
# get_agent_identity.sh - Standard agent identity helper
# Returns stable agent identity for use in git trailers, logs, and coordination

set -euo pipefail

# DX_AGENT_ID identity standard (bd-n1rv)
# Format: <magicdns-host>-<platform>
# Examples:
#   - macmini-codex-cli
#   - epyc6-antigravity

# Fallback order:
# 1. DX_AGENT_ID (if set and non-empty)
# 2. AGENT_NAME (legacy, if set and non-empty)
# 3. Auto-detect: hostname-tool

get_platform() {
  # Detect platform/tool from environment or process
  if [[ -n "${CLAUDE_CODE:-}" ]]; then
    echo "claude-code"
  elif [[ -n "${CODEX_CLI:-}" ]]; then
    echo "codex-cli"
  elif [[ -n "${ANTIGRAVITY:-}" ]]; then
    echo "antigravity"
  elif command -v claude >/dev/null 2>&1; then
    echo "claude-code"
  elif command -v codex >/dev/null 2>&1; then
    echo "codex-cli"
  else
    echo "unknown"
  fi
}

get_hostname() {
  # Prefer canonical host key mapping (avoids provider hostnames like v220...).
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CANONICAL_TARGETS_SH="$SCRIPT_DIR/canonical-targets.sh"
  if [[ -f "$CANONICAL_TARGETS_SH" ]]; then
    # shellcheck disable=SC1090
    source "$CANONICAL_TARGETS_SH"
    if command -v detect_host_key >/dev/null 2>&1; then
      detect_host_key
      return 0
    fi
  fi

  # Fallback to hostname -s (short), then hostname
  hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown"
}

# Main identity resolution
if [[ -n "${DX_AGENT_ID:-}" ]]; then
  # Use DX_AGENT_ID if set (highest priority)
  echo "$DX_AGENT_ID"
elif [[ -n "${AGENT_NAME:-}" ]]; then
  # Fallback to AGENT_NAME (legacy)
  echo "$AGENT_NAME"
else
  # Auto-detect: hostname-platform
  HOSTNAME="$(get_hostname)"
  PLATFORM="$(get_platform)"
  echo "${HOSTNAME}-${PLATFORM}"
fi
