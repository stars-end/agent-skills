#!/usr/bin/env bash
# ensure-shell-path.sh
# Ensure non-interactive shells have a safe PATH that includes ~/.local/bin and ~/bin.
# Never writes secrets.

set -euo pipefail

DOLT_HUB_MARKER_START="# >>> beads dolt hub defaults (v1)"
DOLT_HUB_MARKER_END="# <<< beads dolt hub defaults (v1)"
DOLT_HUB_HOST_DEFAULT="100.107.173.83"
DOLT_HUB_PORT_DEFAULT="3307"

ensure_dolt_hub_defaults() {
  local rc_file="$1"
  if [[ -f "$rc_file" ]] && grep -Fq "$DOLT_HUB_MARKER_START" "$rc_file"; then
    return 0
  fi

  {
    echo ""
    echo "$DOLT_HUB_MARKER_START"
    echo "export BEADS_DOLT_SERVER_HOST=\"\${BEADS_DOLT_SERVER_HOST:-$DOLT_HUB_HOST_DEFAULT}\""
    echo "export BEADS_DOLT_SERVER_PORT=\"\${BEADS_DOLT_SERVER_PORT:-$DOLT_HUB_PORT_DEFAULT}\""
    echo "$DOLT_HUB_MARKER_END"
  } >> "$rc_file"
}

ensure_zshenv_path() {
  local zshenv="$HOME/.zshenv"
  local marker="# agent-skills: shell bootstrap (no secrets)"

  if [[ -f "$zshenv" ]] && grep -Fq "$marker" "$zshenv"; then
    # Upgrade path line if an older bootstrap exists (missing common tool dirs).
    if ! grep -Fq "/opt/homebrew/bin" "$zshenv" || ! grep -Fq "/home/linuxbrew/.linuxbrew/bin" "$zshenv"; then
      {
        echo ""
        echo "# agent-skills: shell bootstrap upgrade (no secrets)"
        echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"'
      } >> "$zshenv"
    fi
    ensure_dolt_hub_defaults "$zshenv"
    return 0
  fi

  {
    echo ""
    echo "$marker"
    echo "# NOTE: ~/.zshenv runs for non-interactive shells; do not put tokens here."
    echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"'
    echo "export BEADS_IGNORE_REPO_MISMATCH=1"
  } >> "$zshenv"
  ensure_dolt_hub_defaults "$zshenv"
}

ensure_bash_profile_path() {
  # For macOS and some Linux distros, non-interactive SSH might load bash as login shell.
  # Keep this minimal and secret-free.
  local profile="$HOME/.bash_profile"
  local marker="# agent-skills: shell bootstrap (no secrets)"

  if [[ -f "$profile" ]] && grep -Fq "$marker" "$profile"; then
    if ! grep -Fq "/opt/homebrew/bin" "$profile" || ! grep -Fq "/home/linuxbrew/.linuxbrew/bin" "$profile"; then
      {
        echo ""
        echo "# agent-skills: shell bootstrap upgrade (no secrets)"
        echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"'
      } >> "$profile"
    fi
    ensure_dolt_hub_defaults "$profile"
    return 0
  fi

  {
    echo ""
    echo "$marker"
    echo "# NOTE: Do not put tokens here."
    echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"'
    echo "export BEADS_IGNORE_REPO_MISMATCH=1"
  } >> "$profile"
  ensure_dolt_hub_defaults "$profile"
}

main() {
  mkdir -p "$HOME/.local/bin" "$HOME/bin"
  ensure_zshenv_path
  ensure_bash_profile_path
}

main "$@"
