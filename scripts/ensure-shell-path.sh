#!/usr/bin/env bash
# ensure-shell-path.sh
# Ensure non-interactive shells have a safe PATH that includes ~/.local/bin and ~/bin.
# Never writes secrets.

set -euo pipefail

ensure_zshenv_path() {
  local zshenv="$HOME/.zshenv"
  local marker="# agent-skills: shell bootstrap (no secrets)"

  if [[ -f "$zshenv" ]] && grep -Fq "$marker" "$zshenv"; then
    # Upgrade path line if an older bootstrap exists (without mise shims).
    if ! grep -Fq "mise/shims" "$zshenv"; then
      {
        echo ""
        echo "# agent-skills: shell bootstrap upgrade (no secrets)"
        echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:$PATH"'
      } >> "$zshenv"
    fi
    return 0
  fi

  {
    echo ""
    echo "$marker"
    echo "# NOTE: ~/.zshenv runs for non-interactive shells; do not put tokens here."
    echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:$PATH"'
  } >> "$zshenv"
}

ensure_bash_profile_path() {
  # For macOS and some Linux distros, non-interactive SSH might load bash as login shell.
  # Keep this minimal and secret-free.
  local profile="$HOME/.bash_profile"
  local marker="# agent-skills: shell bootstrap (no secrets)"

  if [[ -f "$profile" ]] && grep -Fq "$marker" "$profile"; then
    if ! grep -Fq "mise/shims" "$profile"; then
      {
        echo ""
        echo "# agent-skills: shell bootstrap upgrade (no secrets)"
        echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:$PATH"'
      } >> "$profile"
    fi
    return 0
  fi

  {
    echo ""
    echo "$marker"
    echo "# NOTE: Do not put tokens here."
    echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:$PATH"'
  } >> "$profile"
}

main() {
  mkdir -p "$HOME/.local/bin" "$HOME/bin"
  ensure_zshenv_path
  ensure_bash_profile_path
}

main "$@"
