#!/usr/bin/env bash
# install-mise.sh
# Best-effort mise installer for Linux/macOS.
# Safe-by-default: does not write secrets.

set -euo pipefail

if command -v mise >/dev/null 2>&1; then
  echo "mise already installed: $(mise --version 2>/dev/null | head -1 || echo ok)"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing curl; cannot install mise automatically." >&2
  exit 1
fi

echo "Installing mise..."
curl -fsSL https://mise.jdx.dev/install.sh | sh

echo "Installed mise. Ensure PATH includes mise shims:"
echo "  export PATH=\"$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:$PATH\""
