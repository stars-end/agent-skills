#!/usr/bin/env bash
set -euo pipefail

echo "🩺 mcp-doctor — canonical MCP + CLI checks (no secrets)"

STRICT="${MCP_DOCTOR_STRICT:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SKILLS_DIR:-"$(cd "${SCRIPT_DIR}/.." && pwd)"}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

FILES=(
  "$REPO_ROOT/.claude/settings.json"
  "$REPO_ROOT/.vscode/mcp.json"
  "$REPO_ROOT/codex.mcp.json"
  "$REPO_ROOT/gemini.mcp.json"
  "$REPO_ROOT/.mcp.json"
  "$REPO_ROOT/opencode.json"
  "$HOME/.claude/settings.json"
  "$HOME/.claude.json"
  "$HOME/.codex/config.toml"
  "$HOME/.gemini/settings.json"
)

have_in_files() {
  local needle="$1"
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    if rg -F -q "$needle" "$f" 2>/dev/null; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

missing_required=0
missing_optional=0

echo ""
echo "REQUIRED MCP servers:"

# 1) universal-skills (REQUIRED - skills plane)
if f="$(have_in_files \"universal-skills\")" || f="$(have_in_files \"skills\")"; then
  echo "✅ skills (universal-skills) (config seen in: $f)"
else
  echo "❌ skills (universal-skills) (no config found) — REQUIRED"
  missing_required=$((missing_required+1))
fi

echo ""
echo "OPTIONAL MCP servers:"

# 2) agent-mail (OPTIONAL)
if f="$(have_in_files \"mcp-agent-mail\")" || f="$(have_in_files \"agent-mail\")"; then
  echo "✅ agent-mail (config seen in: $f)"
else
  echo "⚠️  agent-mail (no config found) — optional"
  missing_optional=$((missing_optional+1))
fi

# 3) serena (OPTIONAL)
if f="$(have_in_files \"serena\")"; then
  echo "✅ serena (config seen in: $f)"
else
  echo "⚠️  serena (no config found) — optional"
  missing_optional=$((missing_optional+1))
fi

# 4) z.ai search MCP (OPTIONAL)
if f="$(have_in_files \"z.ai\")" || f="$(have_in_files \"api.z.ai\")" || f="$(have_in_files \"search-mcp\")"; then
  echo "✅ z.ai search (config seen in: $f)"
else
  echo "⚠️  z.ai search (no config found) — optional"
  missing_optional=$((missing_optional+1))
fi

echo ""
echo "REQUIRED skills mount:"

# Check ~/.agent/skills -> ~/agent-skills invariant
SKILLS_MOUNT="$HOME/.agent/skills"
AGENT_SKILLS_DIR="$HOME/agent-skills"

if [[ -L "$SKILLS_MOUNT" ]]; then
  TARGET="$(readlink "$SKILLS_MOUNT")"
  if [[ "$TARGET" == "$AGENT_SKILLS_DIR" ]] || [[ "$(cd "$SKILLS_MOUNT" && pwd)" == "$AGENT_SKILLS_DIR" ]]; then
    echo "✅ ~/.agent/skills -> ~/agent-skills (symlink: $TARGET)"
  else
    echo "❌ ~/.agent/skills points to wrong target: $TARGET (expected: $AGENT_SKILLS_DIR)"
    missing_required=$((missing_required+1))
  fi
elif [[ -d "$SKILLS_MOUNT" ]]; then
  MOUNT_REAL="$(cd "$SKILLS_MOUNT" && pwd)"
  if [[ "$MOUNT_REAL" == "$AGENT_SKILLS_DIR" ]]; then
    echo "✅ ~/.agent/skills -> ~/agent-skills (directory)"
  else
    echo "❌ ~/.agent/skills exists but is not ~/agent-skills: $MOUNT_REAL"
    missing_required=$((missing_required+1))
  fi
else
  echo "❌ ~/.agent/skills does not exist — REQUIRED"
  echo "   Run: ln -sfn ~/agent-skills ~/.agent/skills"
  missing_required=$((missing_required+1))
fi

echo ""
echo "Agent-skills repo freshness:"

# Check if ~/agent-skills is a git repo and compare with origin/main
if [[ -d "$AGENT_SKILLS_DIR/.git" ]]; then
  cd "$AGENT_SKILLS_DIR" || true
  # Fetch only if this is a fresh check (optional, avoid network on every run)
  # git fetch origin main >/dev/null 2>&1 || true

  LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null || echo "unknown")

  if [[ "$LOCAL_HASH" == "unknown" ]] || [[ "$REMOTE_HASH" == "unknown" ]]; then
    echo "⚠️  ~/agent-skills: unable to check repo freshness"
    missing_optional=$((missing_optional+1))
  elif [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
    echo "✅ ~/agent-skills: up to date with origin/main"
  else
    # Check if local is behind
    if git merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
      BEHIND_COUNT=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
      echo "⚠️  ~/agent-skills: behind origin/main by $BEHIND_COUNT commits"
      echo "   Run: cd ~/agent-skills && git pull origin main"
      missing_optional=$((missing_optional+1))
    elif git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
      AHEAD_COUNT=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
      echo "✅ ~/agent-skills: ahead of origin/main by $AHEAD_COUNT commits"
    else
      echo "⚠️  ~/agent-skills: diverged from origin/main (needs rebase or merge)"
      echo "   Run: cd ~/agent-skills && git status"
      missing_optional=$((missing_optional+1))
    fi
  fi
  cd - >/dev/null 2>&1 || true
else
  echo "⚠️  ~/agent-skills: not a git repository"
  missing_optional=$((missing_optional+1))
fi

echo ""
echo "OPTIONAL CLI tools:"

if command -v railway >/dev/null 2>&1; then
  echo "✅ railway ($(railway --version 2>/dev/null | head -1 || echo installed))"
  
  # Check Login Status
  if ! railway whoami >/dev/null 2>&1; then
    echo "⚠️  railway: NOT LOGGED IN. Run 'railway login'."
    missing_optional=$((missing_optional+1))
  fi

  # Check Railway Shell Context
  if [[ -z "${RAILWAY_PROJECT_ID:-}" ]] && [[ -z "${RAILWAY_ENVIRONMENT:-}" ]]; then
    echo "⚠️  railway: NOT IN SHELL. Most commands require 'railway shell'."
    missing_optional=$((missing_optional+1))
  else
    echo "✅ railway: inside active shell context"
  fi
else
  echo "⚠️  railway (not installed) — optional"
  missing_optional=$((missing_optional+1))
fi

if command -v gh >/dev/null 2>&1; then
  echo "✅ gh ($(gh --version 2>/dev/null | head -1 || echo installed))"
else
  echo "⚠️  gh (not installed) — optional"
  missing_optional=$((missing_optional+1))
fi

echo ""
if [[ "$missing_required" -eq 0 ]]; then
  if [[ "$missing_optional" -eq 0 ]]; then
    echo "✅ mcp-doctor: healthy (all required + optional items present)"
  else
    echo "✅ mcp-doctor: healthy (required items present, $missing_optional optional items missing)"
  fi
  exit 0
fi

echo "❌ mcp-doctor: $missing_required REQUIRED items missing"
if [[ "$missing_optional" -gt 0 ]]; then
  echo "⚠️  Also missing $missing_optional optional items"
fi
echo ""
echo "Setup instructions: $SKILLS_DIR/mcp-doctor/SKILL.md"
if [[ "$STRICT" == "1" ]]; then
  exit 1
fi
exit 0
