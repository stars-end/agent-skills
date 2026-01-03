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

# 1. Symlink Configuration (NTM)
# NOTE: Serena removed due to 99% CPU runaway issues (2026-01-03)
echo -e "${GREEN} -> Linking configurations...${RESET}"
mkdir -p "$AGENTS_ROOT/configs/ntm"
ln -sf "$AGENTS_ROOT/configs/ntm/cockpit.yaml" "$HOME/.ntm.yaml"
# Serena disabled - causing MCP server to consume 99% CPU
# mkdir -p "$HOME/.serena"
# ln -sf "$AGENTS_ROOT/configs/serena/config.toml" "$HOME/.serena/config.toml"

# 2. Setup ~/.agent/skills Invariant
echo -e "${GREEN} -> Setting up skills mount (~/.agent/skills)...${RESET}"
mkdir -p "$HOME/.agent"
ln -sfn "$AGENTS_ROOT" "$HOME/.agent/skills"

# 3. Install Smart Tools (run)
echo -e "${GREEN} -> Installing Smart Tools...${RESET}"
ln -sf "$AGENTS_ROOT/tools/run" "$BIN_DIR/run"
chmod +x "$AGENTS_ROOT/tools/run"

# 3.1 Install Hive Tools
echo -e "${GREEN} -> Installing Hive Mind Tools...${RESET}"
ln -sf "$AGENTS_ROOT/hive/orchestrator/hive-status.py" "$BIN_DIR/hive-status"
ln -sf "$AGENTS_ROOT/hive/orchestrator/monitor.py" "$BIN_DIR/hive-monitor"
ln -sf "$AGENTS_ROOT/hive/node/cleanup.sh" "$BIN_DIR/hive-cleanup"
ln -sf "$AGENTS_ROOT/hive/node/hive-queen.py" "$BIN_DIR/hive-queen"
chmod +x "$AGENTS_ROOT/hive/orchestrator/hive-status.py"
chmod +x "$AGENTS_ROOT/hive/orchestrator/monitor.py"
chmod +x "$AGENTS_ROOT/hive/node/cleanup.sh"
chmod +x "$AGENTS_ROOT/hive/node/hive-queen.py"

# 3.2 Install Slack MCP
echo -e "${GREEN} -> Setting up Slack MCP integration...${RESET}"
if [ -f "$AGENTS_ROOT/scripts/slack-mcp-setup.sh" ]; then
    source "$AGENTS_ROOT/scripts/slack-mcp-setup.sh"
fi

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

# 5. Install Hooks (The Physics)
echo -e "${GREEN} -> Installing Git Hooks & Safety Guard...${RESET}"

# Install Claude Hook globally
"$AGENTS_ROOT/git-safety-guard/install.sh" --global

# Install Native Hooks per repo
for repo in "$HOME/prime-radiant-ai" "$HOME/affordabot" "$HOME/llm-common" "$AGENTS_ROOT"; do
    if [ -d "$repo/.git" ]; then
        echo "   Installing hooks in $repo..."
        (cd "$repo" && "$AGENTS_ROOT/git-safety-guard/install.sh")
    fi
done

# Enforce GEMINI.md -> AGENTS.md symlink (Relative)
for repo in "$HOME/prime-radiant-ai" "$HOME/affordabot" "$HOME/llm-common" "$AGENTS_ROOT"; do
    if [ -f "$repo/AGENTS.md" ]; then
        # Use a subshell to change dir safely
        (
            cd "$repo"
            # Remove existing if it's an absolute link or broken
            [ -L GEMINI.md ] && rm GEMINI.md
            ln -sf AGENTS.md GEMINI.md
            echo "   Linked GEMINI.md -> AGENTS.md in $repo"
        )
    fi
done

configure_shell() {
    RC_FILE="$1"
    if [ -f "$RC_FILE" ]; then
        echo "   Configuring $RC_FILE..."
        if ! grep -q "dx-hydrate" "$RC_FILE"; then
            echo "" >> "$RC_FILE"
            echo "# Agent Skills DX" >> "$RC_FILE"
            echo "alias hydrate='$AGENTS_ROOT/scripts/dx-hydrate.sh'" >> "$RC_FILE"
            echo "alias dx-check='$AGENTS_ROOT/scripts/dx-check.sh'" >> "$RC_FILE"
            echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$RC_FILE"
            
            # Auto-check on login
            echo "if [ -f '$AGENTS_ROOT/scripts/dx-status.sh' ]; then" >> "$RC_FILE"
            echo "  '$AGENTS_ROOT/scripts/dx-status.sh' >/dev/null 2>&1 || echo \"⚠️  DX Environment Unhealthy. Run 'dx-check' to fix.\"" >> "$RC_FILE"
            echo "fi" >> "$RC_FILE"
        fi
    fi
}

configure_shell "$HOME/.bashrc"
configure_shell "$HOME/.zshrc"

echo -e "${BLUE}✨ Hydration Complete. ready for multi-agent dispatch.${RESET}"
