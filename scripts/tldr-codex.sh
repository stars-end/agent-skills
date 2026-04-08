#!/usr/bin/env bash
#
# tldr-codex.sh
#
# Stable llm-tldr entrypoint for Codex desktop threads when the MCP tool
# surface is unavailable. This stays intentionally thin: it emits a single
# fallback notice, then delegates to the existing daemon-backed helper.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${TLDR_CODEX_FALLBACK_NOTICE:-1}" != "0" ]]; then
  echo "[llm-tldr] MCP unavailable in-thread; using daemon-backed local fallback." >&2
fi

exec "${SCRIPT_DIR}/tldr-daemon-fallback.sh" "$@"
