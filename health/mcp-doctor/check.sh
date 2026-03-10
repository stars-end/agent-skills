#!/usr/bin/env bash
set -euo pipefail

echo "🩺 mcp-doctor — canonical MCP + CLI checks (no secrets)"

STRICT="${MCP_DOCTOR_STRICT:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SKILLS_DIR:-"$(cd "${SCRIPT_DIR}/../.." && pwd)"}"
MANIFEST_PATH="${SKILLS_DIR}/configs/fleet-sync.manifest.yaml"
CANONICAL_TARGETS="${SKILLS_DIR}/scripts/canonical-targets.sh"

echo ""
echo "=========================================================="
echo " MCP Client Contract Diagnosis"
echo " Reference: docs/runbook/fleet-sync/client-mcp-contract.md"
echo "=========================================================="

missing_required=0
missing_optional=0
client_warnings=0

check_mcp_client() {
  local client_name="$1"
  local config_path="$2"
  local check_key="$3"
  local list_cmd="$4"
  local list_grep="$5"
  local expected_status="$6" # VERIFIED or INFERRED or BLOCKED

  echo -n "- $client_name: "
  
  if [[ ! -f "$config_path" ]]; then
    echo "⚠️  Config missing ($config_path)"
    client_warnings=$((client_warnings+1))
    return
  fi

  if ! grep -q "$check_key" "$config_path" 2>/dev/null; then
    echo "⚠️  Config exists but missing key '$check_key' ($config_path)"
    client_warnings=$((client_warnings+1))
    return
  fi

  if [[ "$expected_status" == "BLOCKED" ]]; then
    echo "❌ Configured but BLOCKED"
    client_warnings=$((client_warnings+1))
    return
  fi

  if [[ "$list_cmd" == "none" ]]; then
    echo "✅ Configured ($config_path) [Status: $expected_status]"
    return
  fi

  if ! command -v $(echo "$list_cmd" | awk '{print $1}') >/dev/null 2>&1; then
    echo "⚠️  CLI not found ($(echo "$list_cmd" | awk '{print $1}'))"
    client_warnings=$((client_warnings+1))
    return
  fi

  local out
  out=$(eval "$list_cmd" 2>&1 || true)
  if ! echo "$out" | grep -q "$list_grep"; then
    echo "⚠️  Configured but tool '$list_grep' not visible in list output"
    client_warnings=$((client_warnings+1))
    return
  fi

  echo "✅ Configured and Visible ($config_path) [Status: $expected_status]"
}

echo ""
echo "Client Configuration & Visibility:"
# check_mcp_client name path key "list cmd" "grep string" "STATUS"
check_mcp_client "claude-code" "$HOME/.claude.json" "mcpServers" "claude mcp list" "llm-tldr" "VERIFIED"
check_mcp_client "gemini-cli" "$HOME/.gemini/settings.json" "mcpServers" "gemini mcp list" "llm-tldr" "VERIFIED"
check_mcp_client "codex-cli" "$HOME/.codex/config.toml" "mcp_servers" "codex mcp list" "llm-tldr" "VERIFIED"
check_mcp_client "opencode" "$HOME/.config/opencode/opencode.jsonc" "\"mcp\"" "opencode mcp list" "llm-tldr" "VERIFIED"
check_mcp_client "antigravity" "$HOME/.gemini/settings.json" "mcpServers" "none" "" "INFERRED"

echo ""
echo "=========================================================="
echo " Legacy / Optional Tool Checks"
echo "=========================================================="

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

FILES_BASE=(
  "$REPO_ROOT/.claude/settings.json"
  "$REPO_ROOT/.vscode/mcp.json"
  "$REPO_ROOT/codex.mcp.json"
  "$REPO_ROOT/.mcp.json"
  "$REPO_ROOT/opencode.json"
)

FILES=("${FILES_BASE[@]}")

if [[ -f "$CANONICAL_TARGETS" ]]; then
  # shellcheck disable=SC1090
  source "$CANONICAL_TARGETS"
  if declare -p CANONICAL_IDES >/dev/null 2>&1; then
    for ide in "${CANONICAL_IDES[@]}"; do
      while IFS= read -r artifact; do
        [[ -n "$artifact" ]] && FILES+=("$artifact")
      done < <(get_ide_artifacts "$ide" 2>/dev/null || true)
    done
  fi
fi

GEMINI_GRACE_DAYS=7
GEMINI_ENFORCE_AFTER=7

manifest_scalar() {
  local section="$1"
  local key="$2"
  [[ ! -f "$MANIFEST_PATH" ]] && return
  awk -v section="  ${section}:" -v key="    ${key}:" '
    function trim(v) { gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); return v }
    {
      if ($0 ~ /^audit:/) { in_audit=1; next }
      if (in_audit && /^[^[:space:]]/) { in_audit=0; in_section=0; in_key=0 }
      if (in_audit && $0 ~ "^" section "$") { in_section=1; in_key=0; next }
      if (in_audit && in_section && $0 ~ "^" key) { in_key=1; next }
      if (in_audit && in_section && in_key) {
        value=$0
        sub(/^[[:space:]]+[^:]+:[[:space:]]*/, "", value)
        gsub(/#.*/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^"|"$/, "", value)
        if (value != "") print value
        exit
      }
    }
  ' "$MANIFEST_PATH"
}

load_gemini_enforcement() {
  local grace
  local enforce
  grace="$(manifest_scalar "gemini_enforcement" "grace_days" 2>/dev/null || true)"
  enforce="$(manifest_scalar "gemini_enforcement" "enforce_after" 2>/dev/null || true)"
  [[ -n "$grace" && "$grace" =~ ^[0-9]+$ ]] && GEMINI_GRACE_DAYS="$grace"
  [[ -n "$enforce" && "$enforce" =~ ^[0-9]+$ ]] && GEMINI_ENFORCE_AFTER="$enforce"
  if [[ "$GEMINI_ENFORCE_AFTER" -lt "$GEMINI_GRACE_DAYS" ]]; then
    GEMINI_ENFORCE_AFTER="$GEMINI_GRACE_DAYS"
  fi
}

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

gemini_enforcement_state() {
  local marker="${HOME}/.dx-state/fleet/enforcement/gemini-enforcement.json"
  local now_epoch
  local first_epoch=""
  local missing=0
  local artifact_paths=(
    "${HOME}/.gemini/GEMINI.md"
    "${HOME}/.gemini/settings.json"
  )
  local artifact
  local has_binary=0

  if [[ -x "${HOME}/.gemini/gemini" ]] || [[ -x "${HOME}/.gemini/gemini-cli" ]] || command -v gemini >/dev/null 2>&1 || command -v gemini-cli >/dev/null 2>&1; then
    has_binary=1
  fi

  for artifact in "${artifact_paths[@]}"; do
    [[ -f "$artifact" ]] && continue
    missing=1
  done
  if [[ "$missing" -eq 0 ]] && [[ "$has_binary" -eq 1 ]]; then
    if [[ -f "$marker" ]]; then
      rm -f "$marker"
    fi
    echo "pass"
    return
  fi

  if [[ "$missing" -eq 0 ]]; then
    echo "warn"
    return
  fi

  now_epoch="$(date -u +%s)"
  mkdir -p "$(dirname "$marker")"
  if [[ -f "$marker" ]]; then
    first_epoch="$(sed -n '1p' "$marker" 2>/dev/null || printf '')"
  fi
  if [[ -z "$first_epoch" || ! "$first_epoch" =~ ^[0-9]+$ ]]; then
    first_epoch="$now_epoch"
    printf '%s\n' "$first_epoch" > "$marker"
  fi
  local days_missing=$(( (now_epoch - first_epoch) / 86400 ))
  if [[ "$days_missing" -le "$GEMINI_GRACE_DAYS" ]]; then
    echo "warn"
    return
  fi
  if [[ "$days_missing" -gt "$GEMINI_ENFORCE_AFTER" ]]; then
    echo "fail"
  else
    echo "warn"
  fi
}

load_gemini_enforcement

echo ""
echo "OPTIONAL MCP servers:"

# 4) slack MCP (OPTIONAL)
if f="$(have_in_files '\"slack\"')" || f="$(have_in_files \"slack-mcp\")" || f="$(have_in_files \"slack-mcp-server\")"; then
  echo "✅ slack (config seen in: $f)"
else
  echo "⚠️  slack (no config found) — optional"
  missing_optional=$((missing_optional+1))
fi

# 5) z.ai search MCP (OPTIONAL)
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

# Check if ~/agent-skills is a git repo and compare with trunk (origin/HEAD → origin/master → origin/main)
if [[ -d "$AGENT_SKILLS_DIR/.git" ]]; then
  cd "$AGENT_SKILLS_DIR" || true
  # Fetch only if this is a fresh check (optional, avoid network on every run)
  # git fetch origin >/dev/null 2>&1 || true

  TRUNK_REF="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -z "$TRUNK_REF" ]]; then
    if git show-ref --verify --quiet refs/remotes/origin/master; then
      TRUNK_REF="origin/master"
    elif git show-ref --verify --quiet refs/remotes/origin/main; then
      TRUNK_REF="origin/main"
    fi
  fi

  LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  REMOTE_HASH=$(git rev-parse "$TRUNK_REF" 2>/dev/null || echo "unknown")

  if [[ -z "${TRUNK_REF:-}" ]] || [[ "$LOCAL_HASH" == "unknown" ]] || [[ "$REMOTE_HASH" == "unknown" ]]; then
    echo "⚠️  ~/agent-skills: unable to check repo freshness"
    missing_optional=$((missing_optional+1))
  elif [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
    echo "✅ ~/agent-skills: up to date with $TRUNK_REF"
  else
    # Check if local is behind
    if git merge-base --is-ancestor HEAD "$TRUNK_REF" 2>/dev/null; then
      BEHIND_COUNT=$(git rev-list --count HEAD.."$TRUNK_REF" 2>/dev/null || echo "?")
      echo "⚠️  ~/agent-skills: behind $TRUNK_REF by $BEHIND_COUNT commits"
      echo "   Run: cd ~/agent-skills && git pull origin ${TRUNK_REF#origin/}"
      missing_optional=$((missing_optional+1))
    elif git merge-base --is-ancestor "$TRUNK_REF" HEAD 2>/dev/null; then
      AHEAD_COUNT=$(git rev-list --count "$TRUNK_REF"..HEAD 2>/dev/null || echo "?")
      echo "✅ ~/agent-skills: ahead of $TRUNK_REF by $AHEAD_COUNT commits"
    else
      echo "⚠️  ~/agent-skills: diverged from $TRUNK_REF (needs rebase or merge)"
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
echo "Git trunk alignment (canonical clones):"

CANONICAL_TARGETS_SH="$SKILLS_DIR/scripts/canonical-targets.sh"
if [[ -f "$CANONICAL_TARGETS_SH" ]]; then
  # shellcheck disable=SC1090
  source "$CANONICAL_TARGETS_SH"
fi

CANONICAL_TRUNK="${CANONICAL_TRUNK_BRANCH:-master}"

repo_warns=0
if declare -p CANONICAL_REPOS >/dev/null 2>&1 && [[ "${#CANONICAL_REPOS[@]}" -gt 0 ]]; then
  for repo in "${CANONICAL_REPOS[@]}"; do
    repo_path="$HOME/$repo"
    if [[ ! -d "$repo_path/.git" ]]; then
      echo "⚠️  $repo_path (missing repo) — expected canonical clone"
      repo_warns=$((repo_warns+1))
      continue
    fi

    current_branch="$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "")"
    if [[ -z "$current_branch" ]]; then
      current_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    fi

    if [[ "$current_branch" != "$CANONICAL_TRUNK" ]]; then
      echo "⚠️  $repo_path: on '$current_branch' (expected '$CANONICAL_TRUNK') — keep canonical clones on trunk for automation"
      repo_warns=$((repo_warns+1))
    else
      echo "✅ $repo_path: on $CANONICAL_TRUNK"
    fi

    if [[ -n "$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)" ]]; then
      echo "⚠️  $repo_path: working tree dirty — ru/dx automation will refuse to fast-forward"
      repo_warns=$((repo_warns+1))
    fi
  done
else
  echo "⚠️  Canonical repo list not found (expected: $CANONICAL_TARGETS_SH)"
  repo_warns=$((repo_warns+1))
fi

if [[ "$repo_warns" -gt 0 ]]; then
  missing_optional=$((missing_optional+repo_warns))
fi

echo ""
echo "OPTIONAL CLI tools:"

if command -v railway >/dev/null 2>&1; then
  echo "✅ railway ($(railway --version 2>/dev/null | head -1 || echo installed))"
  if ! railway whoami >/dev/null 2>&1; then
    echo "⚠️  railway: NOT LOGGED IN (optional for local dev, run 'railway login' when needed)"
    missing_optional=$((missing_optional+1))
  else
    echo "✅ railway: authenticated (interactive session)"
  fi
  if [[ -n "${RAILWAY_API_TOKEN:-}" ]]; then
    echo "✅ railway: RAILWAY_API_TOKEN set (shell context for automated workflows)"
  elif [[ -n "${RAILWAY_TOKEN:-}" ]]; then
    echo "⚠️  railway: legacy RAILWAY_TOKEN set (prefer RAILWAY_API_TOKEN)"
  elif [[ -n "${RAILWAY_PROJECT_ID:-}" ]] || [[ -n "${RAILWAY_ENVIRONMENT:-}" ]]; then
    echo "✅ railway: inside Railway shell context (PROJECT_ID/ENVIRONMENT set)"
  else
    echo "⚠️  railway: NOT IN SHELL (optional for local dev, see ENV_SOURCES_CONTRACT.md)"
    echo "   For CI/CD: export RAILWAY_API_TOKEN=\$(op read 'op://dev/Agent-Secrets-Production/RAILWAY_API_TOKEN')"
    missing_optional=$((missing_optional+1))
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
echo "Canonical Gemini CLI lane:"
gemini_state="$(gemini_enforcement_state)"
if [[ "$gemini_state" == "pass" ]]; then
  echo "✅ gemini-cli lane present and compliant"
elif [[ "$gemini_state" == "warn" ]]; then
  echo "⚠️  gemini-cli lane missing artifacts; allowed in grace window (${GEMINI_GRACE_DAYS} day(s), enforce after ${GEMINI_ENFORCE_AFTER} day(s))"
  echo "   Ensure: ~/.gemini/GEMINI.md, ~/.gemini/gemini or ~/.gemini/gemini-cli, ~/.gemini/settings.json"
  missing_optional=$((missing_optional+1))
else
  echo "❌ gemini-cli lane missing beyond grace window"
  echo "   Ensure: ~/.gemini/GEMINI.md, ~/.gemini/gemini or ~/.gemini/gemini-cli, ~/.gemini/settings.json"
  missing_optional=$((missing_optional+1))
fi

echo ""
echo "SLACK MCP configuration (canonical IDEs):"

SLACK_MCP_CONFIGURED=false

if [[ -f "$HOME/.gemini/settings.json" ]]; then
  if grep -q '"slack"' "$HOME/.gemini/settings.json" 2>/dev/null || \
     grep -q 'slack-mcp-server' "$HOME/.gemini/settings.json" 2>/dev/null; then
    echo "✅ gemini-cli/antigravity: Slack MCP configured"
    SLACK_MCP_CONFIGURED=true
  fi
fi

if [[ -f "$HOME/.claude.json" ]]; then
  if grep -q '"slack"' "$HOME/.claude.json" 2>/dev/null || \
     grep -q 'slack-mcp-server' "$HOME/.claude.json" 2>/dev/null; then
    echo "✅ claude-code: Slack MCP configured"
    SLACK_MCP_CONFIGURED=true
  fi
fi

if [[ -f "$HOME/.codex/config.toml" ]]; then
  if grep -q "slack" "$HOME/.codex/config.toml" 2>/dev/null || \
     grep -q "slack-mcp-server" "$HOME/.codex/config.toml" 2>/dev/null; then
    echo "✅ codex-cli: Slack MCP configured"
    SLACK_MCP_CONFIGURED=true
  fi
fi

if [[ -f "$HOME/.config/opencode/opencode.jsonc" ]]; then
  if grep -q '"slack"' "$HOME/.config/opencode/opencode.jsonc" 2>/dev/null || \
     grep -q 'slack-mcp-server' "$HOME/.config/opencode/opencode.jsonc" 2>/dev/null; then
    echo "✅ opencode: Slack MCP configured"
    SLACK_MCP_CONFIGURED=true
  fi
fi

if [[ "$SLACK_MCP_CONFIGURED" == "false" ]]; then
  echo "⚠️  Slack MCP not configured in any canonical IDE"
  echo "   Run: ~/agent-skills/scripts/setup-slack-mcp.sh --all"
  missing_optional=$((missing_optional+1))
fi

echo ""
echo "SSH Key Doctor:"
if [[ -x "$HOME/agent-skills/ssh-key-doctor/check.sh" ]]; then
  echo "✅ ssh-key-doctor installed"
else
  echo "⚠️  ssh-key-doctor not installed — optional"
  echo "   Run: ~/agent-skills/ssh-key-doctor/check.sh"
  missing_optional=$((missing_optional+1))
fi

echo ""
if [[ "$missing_required" -eq 0 ]] && [[ "$client_warnings" -eq 0 ]]; then
  if [[ "$missing_optional" -eq 0 ]]; then
    echo "✅ mcp-doctor: healthy (all required + optional items present)"
  else
    echo "✅ mcp-doctor: healthy (required items present, $missing_optional optional items missing)"
  fi
  exit 0
fi

if [[ "$missing_required" -gt 0 ]]; then
  echo "❌ mcp-doctor: $missing_required REQUIRED items missing"
fi
if [[ "$client_warnings" -gt 0 ]]; then
  echo "⚠️  mcp-doctor: $client_warnings MCP Client Contract warnings"
fi
if [[ "$missing_optional" -gt 0 ]]; then
  echo "⚠️  Also missing $missing_optional optional items"
fi
echo ""
echo "Setup instructions: $SKILLS_DIR/mcp-doctor/SKILL.md"
if [[ "$STRICT" == "1" ]]; then
  exit 1
fi
exit 0
