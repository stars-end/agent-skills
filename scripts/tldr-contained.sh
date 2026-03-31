#!/usr/bin/env bash
#
# tldr-contained.sh
#
# Containment wrapper for llm-tldr that keeps `.tldr` and `.tldrignore`
# strictly outside the project tree.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLM_TLDR_BIN="${LLM_TLDR_BIN:-$(command -v llm-tldr)}"
PYTHON_BIN="$(head -n 1 "${LLM_TLDR_BIN}" | sed 's/^#!//')"
exec "${PYTHON_BIN:-python3}" "${SCRIPT_DIR}/tldr-contained-cli.py" "$@"
