#!/usr/bin/env bash
#
# tldr-daemon-fallback.sh
#
# Contained llm-tldr fallback helper that preserves daemon/socket behavior.
# Uses tldr-daemon-fallback.py, which calls tldr.mcp_server tool functions
# (`_send_command` path) instead of plain tldr CLI direct API calls.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLM_TLDR_BIN="${LLM_TLDR_BIN:-$(command -v llm-tldr)}"
PYTHON_BIN="$(head -n 1 "${LLM_TLDR_BIN}" | sed 's/^#!//')"
exec "${PYTHON_BIN:-python3}" "${SCRIPT_DIR}/tldr-daemon-fallback.py" "$@"
