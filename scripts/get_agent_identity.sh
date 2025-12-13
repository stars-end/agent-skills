#!/usr/bin/env bash
# get_agent_identity.sh - Standard agent identity helper
# Returns stable agent identity for use in git trailers, logs, and coordination

set -euo pipefail

# DX_AGENT_ID identity standard (bd-n1rv)
# Format: <magicdns-host>-<platform>
# Examples:
#   - v2202509262171386004-claude-code
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
  # Try hostname -s first (short hostname), fallback to hostname
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
