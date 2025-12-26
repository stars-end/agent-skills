#!/bin/bash
# dx-hydrate.sh
# Universal bootstrap for the "Solo Dev + 5 Agents" Command Center.

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${BLUE}💧 Hydrating Agent Command Center...${RESET}"

AGENTS_ROOT="$HOME/agent-skills"
BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

# 1. Symlink Configuration (NTM, Serena)
echo -e "${GREEN} -> Linking configurations...${RESET}"
mkdir -p "$AGENTS_ROOT/configs/ntm"
ln -sf "$AGENTS_ROOT/configs/ntm/cockpit.yaml" "$HOME/.ntm.yaml"
mkdir -p "$HOME/.serena"
ln -sf "$AGENTS_ROOT/configs/serena/config.toml" "$HOME/.serena/config.toml"

# 2. Setup ~/.agent/skills Invariant
echo -e "${GREEN} -> Setting up skills mount (~/.agent/skills)...${RESET}"
mkdir -p "$HOME/.agent"
ln -sfn "$AGENTS_ROOT" "$HOME/.agent/skills"

# 3. Install Smart Tools (run)
echo -e "${GREEN} -> Installing Smart Tools...${RESET}"
ln -sf "$AGENTS_ROOT/tools/run" "$BIN_DIR/run"
chmod +x "$AGENTS_ROOT/tools/run"

# 4. Setup Cass (Memory)
echo -e "${GREEN} -> Configuring Cass Memory...${RESET}"
mkdir -p "$HOME/.cass"
cat > "$HOME/.cass/settings.json" <<EOF
{
  "memory_paths": [
    "$AGENTS_ROOT/memory/playbooks",
    "$AGENTS_ROOT/memory/anti_patterns"
  ],
  "index_git_history": true
}
EOF

# 5. Install Hooks (Anti-Corruption)
echo -e "${GREEN} -> Installing Git Hooks...${RESET}"
HOOK_SCRIPT="$AGENTS_ROOT/scripts/validate_beads.py"

install_hook() {
    REPO_PATH="$1"
    if [ -d "$REPO_PATH/.git" ]; then
        echo "   Installing pre-commit in $REPO_PATH"
        HOOK_FILE="$REPO_PATH/.git/hooks/pre-commit"
        echo "#!/bin/bash" > "$HOOK_FILE"
        echo "# Hydrated by dx-hydrate.sh" >> "$HOOK_FILE"
        echo "python3 \"$HOOK_SCRIPT\"" >> "$HOOK_FILE"
        chmod +x "$HOOK_FILE"
    else
        echo "   Skipping $REPO_PATH (not a git repo)"
    fi
}

install_hook "$HOME/prime-radiant-ai"
install_hook "$HOME/affordabot"

# 6. Tool Check
echo -e "${GREEN} -> Checking for required tools...${RESET}"
if ! command -v universal-skills >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  universal-skills not found in PATH.${RESET}"
    echo "   Recommended: npm install -g universal-skills"
fi

# 7. Refresh Environment
echo -e "${GREEN} -> Refreshing environment...${RESET}"
if ! grep -q "dx-hydrate" "$HOME/.bashrc"; then
    echo "alias hydrate='$AGENTS_ROOT/scripts/dx-hydrate.sh'" >> "$HOME/.bashrc"
alias dx-check='/home/feng/agent-skills/scripts/dx-check.sh'
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
fi

echo -e "${BLUE}✨ Hydration Complete. ready for multi-agent dispatch.${RESET}"
