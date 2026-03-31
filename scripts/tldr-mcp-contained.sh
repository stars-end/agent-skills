#!/usr/bin/env bash
#
# tldr-mcp-contained.sh
#
# Shell entry point for the contained llm-tldr MCP server.
# Delegates to tldr-mcp-contained.py.
#
# Drop-in replacement for tldr-mcp in IDE MCP configs:
#   "command": "/path/to/scripts/tldr-mcp-contained.sh"
#   "args": []
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/tldr-mcp-contained.py" "$@"
