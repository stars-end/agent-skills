#!/bin/bash
# ============================================================
# CANONICAL TARGETS REGISTRY
# ============================================================
#
# Single source of truth for canonical VMs, IDEs, and paths.
# Source this file to get environment variables for targets.
#
# Usage:
#   source scripts/canonical-targets.sh
#   echo $CANONICAL_VMS
#   echo $CANONICAL_IDES
#
# ============================================================

# ------------------------------------------------------------
# Canonical VM Hosts (SSH targets)
# ------------------------------------------------------------
# These are the primary VMs used for development and deployment.
# Format: "user@hostname:OS:Description"

# Canonical repos use the default branch on GitHub. In this org we standardize on `master`.
# Override for experiments via: export CANONICAL_TRUNK_BRANCH=main
export CANONICAL_TRUNK_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"

export CANONICAL_VMS=(
  "feng@epyc6:linux:Primary Linux dev host (this machine)"
  "fengning@homedesktop-wsl:linux:WSL2 on Windows - Linux dev environment"
  "fengning@macmini:macos:macOS Dev machine"
)

# Shorthand access to primary targets
export CANONICAL_VM_PRIMARY="feng@epyc6"
export CANONICAL_VM_WSL="fengning@homedesktop-wsl"
export CANONICAL_VM_MACOS="fengning@macmini"

# ------------------------------------------------------------
# Canonical IDE Set
# ------------------------------------------------------------
# These are the supported IDEs for MCP and tooling integration.

export CANONICAL_IDES=(
  "antigravity"
  "claude-code"
  "codex-cli"
  "opencode"
)

# ------------------------------------------------------------
# Canonical Repos (Git)
# ------------------------------------------------------------
# These repos should stay on CANONICAL_TRUNK_BRANCH at their canonical paths,
# so automation (ru, dx-check, pre-flight) can safely fast-forward and verify.

export CANONICAL_REPOS=(
  "agent-skills"
  "prime-radiant-ai"
  "affordabot"
  "llm-common"
)

# ------------------------------------------------------------
# Per-Host Requirements (repos + tools)
# ------------------------------------------------------------
# Some machines intentionally focus on a subset of repos/tools.
# This keeps canonical automation strict where needed, but avoids
# false failures on role-specific machines.
#
# Override detection (optional):
#   export CANONICAL_HOST_KEY=homedesktop-wsl|macmini|vps|local
#

detect_host_key() {
  # Explicit override wins
  if [ -n "${CANONICAL_HOST_KEY:-}" ]; then
    echo "$CANONICAL_HOST_KEY"
    return 0
  fi

  case "$(uname -s 2>/dev/null || true)" in
    Darwin*) echo "macmini" ; return 0 ;;
    Linux*) ;;
  esac

  # Heuristic: WSL
  if [ -r /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    echo "homedesktop-wsl"
    return 0
  fi

  # Default Linux host is epyc6
  echo "epyc6"
}

export CANONICAL_HOST_KEY="$(detect_host_key)"

# Required vs optional repos (by host role)
case "$CANONICAL_HOST_KEY" in
  homedesktop-wsl)
    export CANONICAL_REQUIRED_REPOS=( "agent-skills" "affordabot" "llm-common" )
    export CANONICAL_OPTIONAL_REPOS=( "prime-radiant-ai" )
    ;;
  macmini)
    export CANONICAL_REQUIRED_REPOS=( "agent-skills" "prime-radiant-ai" )
    export CANONICAL_OPTIONAL_REPOS=( "affordabot" "llm-common" )
    ;;
  epyc6)
    export CANONICAL_REQUIRED_REPOS=( "agent-skills" )
    export CANONICAL_OPTIONAL_REPOS=( "prime-radiant-ai" "affordabot" "llm-common" )
    ;;
  *)
    export CANONICAL_REQUIRED_REPOS=( "agent-skills" "prime-radiant-ai" "affordabot" "llm-common" )
    export CANONICAL_OPTIONAL_REPOS=()
    ;;
esac

# Required vs optional tools (by host role)
case "$CANONICAL_HOST_KEY" in
  homedesktop-wsl)
    export CANONICAL_REQUIRED_TOOLS=( "bd" "dcg" "gh" "mise" "op" "railway" "ru" )
    export CANONICAL_OPTIONAL_TOOLS=( "cass" "jules" )
    ;;
  macmini)
    export CANONICAL_REQUIRED_TOOLS=( "bd" "dcg" "gh" "mise" "op" "railway" "ru" )
    export CANONICAL_OPTIONAL_TOOLS=( "cass" "jules" )
    ;;
  epyc6)
    export CANONICAL_REQUIRED_TOOLS=( "bd" "dcg" "gh" "mise" "op" "railway" "ru" )
    export CANONICAL_OPTIONAL_TOOLS=( "cass" "jules" )
    ;;
  *)
    export CANONICAL_REQUIRED_TOOLS=( "bd" "dcg" "gh" "mise" "op" "railway" "ru" )
    export CANONICAL_OPTIONAL_TOOLS=( "cass" "jules" )
    ;;
esac

# ------------------------------------------------------------
# Tool Availability Notes (per-host quirks)
# ------------------------------------------------------------
# epyc6: No jq (no sudo access). Scripts should use grep-based JSON parsing.
# epyc6: User is 'feng' not 'fengning'.
# epyc6: May not be directly reachable - use homedesktop-wsl as jump host.

export CANONICAL_MISSING_TOOLS_EPYC6=( "jq" )

# ------------------------------------------------------------
# SSH Connectivity
# ------------------------------------------------------------
# Not all VMs can reach each other directly. Use jump hosts when needed.
# From VPS/cloud: Use homedesktop-wsl as jump to reach epyc6
#   ssh -J fengning@homedesktop-wsl feng@epyc6

export CANONICAL_JUMP_HOST="fengning@homedesktop-wsl"

# ------------------------------------------------------------
# Per-IDE Config Paths
# ------------------------------------------------------------
# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------

# Get config path for an IDE on current OS
get_ide_config() {
  local ide="$1"
  local os="${2:-$(detect_os)}"

  case "$os" in
    linux|macos)
      ;;
    *)
      echo "Error: Unknown OS '$os'" >&2
      return 1
      ;;
  esac

  case "$ide" in
    antigravity) echo "$HOME/.gemini/antigravity/mcp_config.json" ;;
    claude-code) echo "$HOME/.claude/settings.json" ;;
    codex-cli) echo "$HOME/.codex/config.toml" ;;
    opencode) echo "$HOME/.opencode/config.json" ;;
    *)
      echo "Error: Unknown IDE '$ide'" >&2
      return 1
      ;;
  esac
}

# Detect current OS
detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *)       echo "unknown" ;;
  esac
}

# List all canonical VMs
list_canonical_vms() {
  for vm in "${CANONICAL_VMS[@]}"; do
    echo "$vm"
  done
}

# List all canonical IDEs
list_canonical_ides() {
  for ide in "${CANONICAL_IDES[@]}"; do
    echo "$ide"
  done
}

# SSH to a canonical VM (handles jump hosts automatically)
ssh_canonical_vm() {
  local target="$1"
  shift
  local cmd="$*"

  # Try direct connection first with short timeout
  if ssh -o ConnectTimeout=3 -o BatchMode=yes "$target" true 2>/dev/null; then
    ssh "$target" "$cmd"
  else
    # Use jump host for unreachable targets
    echo "[canonical-targets] Direct SSH failed, using jump host: $CANONICAL_JUMP_HOST" >&2
    ssh "$CANONICAL_JUMP_HOST" "ssh $target \"$cmd\""
  fi
}

# Deploy a file to all canonical VMs
deploy_to_all_vms() {
  local src="$1"
  local dest="$2"
  local base
  base="$(basename "$src")"
  local tmp="/tmp/agentskills-deploy-$base-$$"

  echo "Deploying $src to all canonical VMs..."

  # Direct targets
  for target in "fengning@homedesktop-wsl" "fengning@macmini"; do
    echo "  → $target"
    scp "$src" "$target:$dest" 2>/dev/null && echo "    ✅" || echo "    ❌ Failed"
  done

  # epyc6 via jump host (use homedesktop-wsl as the transfer point)
  echo "  → feng@epyc6 (via jump)"
  if scp "$src" "fengning@homedesktop-wsl:$tmp" 2>/dev/null; then
    ssh fengning@homedesktop-wsl "scp '$tmp' 'feng@epyc6:$dest' && rm -f '$tmp'" 2>/dev/null \
      && echo "    ✅" || echo "    ❌ Failed"
  else
    echo "    ❌ Failed (could not copy to jump host)"
  fi
}

# Export functions for use in subshells
export -f get_ide_config detect_os list_canonical_vms list_canonical_ides ssh_canonical_vm deploy_to_all_vms
