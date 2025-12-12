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

# 1) agent-mail (REQUIRED)
if f="$(have_in_files \"mcp-agent-mail\")" || f="$(have_in_files \"agent-mail\")"; then
  echo "✅ agent-mail (config seen in: $f)"
else
  echo "❌ agent-mail (no config found) — REQUIRED"
  missing_required=$((missing_required+1))
fi

echo ""
echo "OPTIONAL MCP servers:"

# 2) universal-skills (OPTIONAL)
if f="$(have_in_files \"universal-skills\")"; then
  echo "✅ universal-skills (config seen in: $f)"
else
  echo "⚠️  universal-skills (no config found) — optional"
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
echo "OPTIONAL CLI tools:"

if command -v railway >/dev/null 2>&1; then
  echo "✅ railway ($(railway --version 2>/dev/null | head -1 || echo installed))"
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
