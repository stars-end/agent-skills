#!/usr/bin/env bash
set -euo pipefail

# ensure_agent_skills_mount.sh
# Ensures ~/agent-skills exists and:
#   - legacy mount: ~/.agent/skills -> ~/agent-skills (symlink)
#   - canonical skills plane: ~/.agents/skills populated with symlinks to individual skills
# Prints only paths/status, never secrets

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

AGENT_SKILLS_DIR="$HOME/agent-skills"
SKILLS_MOUNT="$HOME/.agent/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"

echo "🔧 Ensuring agent-skills mount..."
echo ""

# 1. Ensure ~/agent-skills exists
if [[ -d "$AGENT_SKILLS_DIR" ]]; then
  log_info "~/agent-skills exists: $AGENT_SKILLS_DIR"

  # Check if it's a git repo
  if [[ -d "$AGENT_SKILLS_DIR/.git" ]]; then
    log_info "  Git repository: $(cd "$AGENT_SKILLS_DIR" && git remote get-url origin 2>/dev/null || echo 'no remote')"
  else
    log_warn "  Not a git repository (expected: stars-end/agent-skills)"
  fi
else
  log_warn "~/agent-skills does not exist. Cloning from GitHub..."

  if git clone https://github.com/stars-end/agent-skills.git "$AGENT_SKILLS_DIR"; then
    log_info "Cloned agent-skills to: $AGENT_SKILLS_DIR"
  else
    log_error "Failed to clone agent-skills. Please clone manually:"
    echo "  git clone https://github.com/stars-end/agent-skills.git ~/agent-skills"
    exit 1
  fi
fi

# 2. Ensure ~/.agent directory exists
if [[ ! -d "$HOME/.agent" ]]; then
  log_info "Creating ~/.agent directory..."
  mkdir -p "$HOME/.agent"
fi

# 3. Ensure ~/.agent/skills -> ~/agent-skills
if [[ -L "$SKILLS_MOUNT" ]]; then
  # It's already a symlink
  TARGET="$(readlink "$SKILLS_MOUNT")"
  REAL_TARGET="$(cd "$SKILLS_MOUNT" && pwd 2>/dev/null || echo '')"

  if [[ "$TARGET" == "$AGENT_SKILLS_DIR" ]] || [[ "$REAL_TARGET" == "$AGENT_SKILLS_DIR" ]]; then
    log_info "~/.agent/skills -> ~/agent-skills (symlink: $TARGET)"
  else
    log_warn "~/.agent/skills points to wrong target: $TARGET"
    log_warn "Re-linking to: $AGENT_SKILLS_DIR"

    rm "$SKILLS_MOUNT"
    ln -sfn "$AGENT_SKILLS_DIR" "$SKILLS_MOUNT"
    log_info "Fixed symlink: ~/.agent/skills -> ~/agent-skills"
  fi
elif [[ -d "$SKILLS_MOUNT" ]]; then
  # It's a directory, not a symlink
  REAL_PATH="$(cd "$SKILLS_MOUNT" && pwd)"

  if [[ "$REAL_PATH" == "$AGENT_SKILLS_DIR" ]]; then
    log_info "~/.agent/skills is already the same as ~/agent-skills (directory)"
  else
    log_warn "~/.agent/skills exists as a directory: $REAL_PATH"
    log_warn "Expected: symlink to ~/agent-skills"

    # Backup existing directory
    BACKUP="${SKILLS_MOUNT}.backup.$(date +%Y%m%d-%H%M%S)"
    log_warn "Moving existing directory to: $BACKUP"
    mv "$SKILLS_MOUNT" "$BACKUP"

    # Create symlink
    ln -sfn "$AGENT_SKILLS_DIR" "$SKILLS_MOUNT"
    log_info "Created symlink: ~/.agent/skills -> ~/agent-skills"
  fi
elif [[ -e "$SKILLS_MOUNT" ]]; then
  # Something else exists at that path
  log_error "~/.agent/skills exists but is not a directory or symlink"
  log_error "Please remove it manually and re-run this script:"
  echo "  rm ~/.agent/skills"
  echo "  $0"
  exit 1
else
  # Doesn't exist, create symlink
  log_info "Creating symlink: ~/.agent/skills -> ~/agent-skills"
  ln -sfn "$AGENT_SKILLS_DIR" "$SKILLS_MOUNT"
  log_info "Symlink created successfully"
fi

# 4. Verify final state
echo ""
echo "Final state:"
echo "  ~/agent-skills: $AGENT_SKILLS_DIR"
if [[ -L "$SKILLS_MOUNT" ]]; then
  echo "  ~/.agent/skills: symlink -> $(readlink "$SKILLS_MOUNT")"
elif [[ -d "$SKILLS_MOUNT" ]]; then
  echo "  ~/.agent/skills: directory ($(cd "$SKILLS_MOUNT" && pwd))"
else
  echo "  ~/.agent/skills: [missing]"
fi

# Ensure ~/.agents/skills exists + install links (best-effort; no secrets).
echo "  ~/.agents/skills: $AGENTS_SKILLS_DIR"
mkdir -p "$AGENTS_SKILLS_DIR"
# Always use canonical installer from ~/agent-skills (not potentially ephemeral worktree)
if [[ -x "$AGENT_SKILLS_DIR/scripts/dx-agents-skills-install.sh" ]]; then
  "$AGENT_SKILLS_DIR/scripts/dx-agents-skills-install.sh" --apply --force >/dev/null 2>&1 || true
elif [[ -x "$AGENT_SKILLS_DIR/scripts/dx-codex-skills-install.sh" ]]; then
  "$AGENT_SKILLS_DIR/scripts/dx-codex-skills-install.sh" --apply --force >/dev/null 2>&1 || true
fi

# 5. Quick health check
echo ""
if [[ -d "$AGENT_SKILLS_DIR" ]] && [[ -e "$SKILLS_MOUNT" ]]; then
  REAL_MOUNT="$(cd "$SKILLS_MOUNT" && pwd 2>/dev/null || echo '')"
  if [[ "$REAL_MOUNT" == "$AGENT_SKILLS_DIR" ]]; then
    log_info "Skills mount is healthy!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify MCP configuration: ~/agent-skills/health/mcp-doctor/check.sh"
    echo "  2. See: ~/agent-skills/SKILLS_PLANE.md for full documentation"
    echo "  3. For Codex skills: ls -la ~/.agents/skills"
    exit 0
  fi
fi

log_error "Skills mount verification failed"
exit 1
