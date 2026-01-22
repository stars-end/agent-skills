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

export CANONICAL_VMS=(
  "fengning@homedesktop-wsl:linux:WSL2 on Windows - Primary Linux dev environment"
  "fengning@macmini:macOS:macOS Dev machine"
  "fengning@v2202509262171386004:linux:VPS (local epyc6)"
)

# Shorthand access to primary targets
export CANONICAL_VM_LINUX="fengning@homedesktop-wsl"
export CANONICAL_VM_MACOS="fengning@macmini"
export CANONICAL_VM_VPS="fengning@v2202509262171386004"

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
# Per-IDE Config Paths
# ------------------------------------------------------------
# Linux (including WSL2)
declare -A CANONICAL_IDE_CONFIG_LINUX=(
  ["antigravity"]="$HOME/.gemini/antigravity/mcp_config.json"
  ["claude-code"]="$HOME/.claude/settings.json"
  ["codex-cli"]="$HOME/.codex/config.toml"
  ["opencode"]="$HOME/.opencode/config.json"
)

# macOS
declare -A CANONICAL_IDE_CONFIG_MACOS=(
  ["antigravity"]="$HOME/.gemini/antigravity/mcp_config.json"
  ["claude-code"]="$HOME/.claude/settings.json"
  ["codex-cli"]="$HOME/.codex/config.toml"
  ["opencode"]="$HOME/.opencode/config.json"
)

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------

# Get config path for an IDE on current OS
get_ide_config() {
  local ide="$1"
  local os="${2:-$(detect_os)}"
  
  case "$os" in
    linux)
      echo "${CANONICAL_IDE_CONFIG_LINUX[$ide]}"
      ;;
    macos)
      echo "${CANONICAL_IDE_CONFIG_MACOS[$ide]}"
      ;;
    *)
      echo "Error: Unknown OS '$os'" >&2
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

# Export functions for use in subshells
export -f get_ide_config detect_os list_canonical_vms list_canonical_ides
