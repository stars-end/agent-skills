#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

RU_URL_DEFAULT="https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/ru"
RU_URL="${RU_URL:-$RU_URL_DEFAULT}"

ensure_path_bootstrap() {
  local zshenv="$HOME/.zshenv"
  local marker="# agent-skills: shell bootstrap (no secrets)"

  if [ -f "$zshenv" ] && grep -Fq "$marker" "$zshenv"; then
    return 0
  fi

  {
    echo ""
    echo "$marker"
    echo "# NOTE: ~/.zshenv runs for non-interactive shells; do not put tokens here."
    echo 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"'
  } >> "$zshenv"
}

main() {
  mkdir -p "$HOME/.local/bin" "$HOME/bin"

  if [ ! -x "$HOME/.local/bin/ru" ]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo -e "${RED}Missing curl; cannot install ru automatically.${RESET}" >&2
      exit 1
    fi
    echo "Downloading ru from: $RU_URL"
    curl -fsSL "$RU_URL" -o "$HOME/.local/bin/ru"
    chmod +x "$HOME/.local/bin/ru"
  fi

  ln -sf "$HOME/.local/bin/ru" "$HOME/bin/ru"
  ensure_path_bootstrap

  echo -e "${GREEN}✓ ru installed${RESET} -> $HOME/.local/bin/ru"
  echo -e "${GREEN}✓ symlink${RESET} -> $HOME/bin/ru"
  echo -e "${GREEN}✓ PATH bootstrap ensured${RESET} -> $HOME/.zshenv"

  if command -v ru >/dev/null 2>&1; then
    ru --version || true
  else
    echo -e "${YELLOW}⚠️  ru not on PATH in this shell.${RESET}"
    echo "Restart your shell or run: source ~/.zshenv"
  fi
}

main "$@"
