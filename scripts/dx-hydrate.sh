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

# Ensure safe PATH bootstrap for non-interactive shells.
"$AGENTS_ROOT/scripts/ensure-shell-path.sh" >/dev/null 2>&1 || true

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

# 3. Install canonical executables in ~/bin
echo -e "${GREEN} -> Ensuring ~/bin tools...${RESET}"
"$AGENTS_ROOT/scripts/dx-ensure-bins.sh" >/dev/null 2>&1 || true

# 3.0 Ensure ru is present (sync control plane)
if ! command -v ru >/dev/null 2>&1; then
  echo -e "${GREEN} -> Installing ru (repo_updater)...${RESET}"
  "$AGENTS_ROOT/scripts/install-ru.sh" >/dev/null 2>&1 || true
fi

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

# 3.3 Install OpenCode Server (Systemd)
echo -e "${GREEN} -> Installing OpenCode systemd service...${RESET}"
mkdir -p "$HOME/.config/systemd/user"
if [ -f "$AGENTS_ROOT/systemd/opencode-server.service" ]; then
    cp "$AGENTS_ROOT/systemd/opencode-server.service" "$HOME/.config/systemd/user/"
    
    # Adjust WorkingDirectory for the current user
    sed -i "s|WorkingDirectory=/home/feng|WorkingDirectory=$HOME|g" "$HOME/.config/systemd/user/opencode-server.service"
    
    # Reload and enable (but don't start - let user do that)
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable opencode-server 2>/dev/null || true
    echo "   OpenCode service installed. Start with: systemctl --user start opencode-server"
else
    echo "   OpenCode service file not found, skipping..."
fi

# 3.4 Install Slack Coordinator (Systemd)
echo -e "${GREEN} -> Installing Slack Coordinator service...${RESET}"
if [ -f "$AGENTS_ROOT/systemd/slack-coordinator.service" ]; then
    cp "$AGENTS_ROOT/systemd/slack-coordinator.service" "$HOME/.config/systemd/user/"
    
    # Adjust paths for current user
    sed -i "s|/home/feng|$HOME|g" "$HOME/.config/systemd/user/slack-coordinator.service"
    
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable slack-coordinator 2>/dev/null || true
    echo "   Coordinator service installed. Start with: systemctl --user start slack-coordinator"
    
    # Create env file if not exists
    if [ ! -f "$HOME/.config/slack-coordinator.env" ]; then
        cat > "$HOME/.config/slack-coordinator.env" <<EOF
OPENCODE_URL=http://localhost:4105
AGENT_NAME=$(hostname -s)
EOF
        echo "   Created coordinator env file: ~/.config/slack-coordinator.env"
    fi
else
    echo "   Coordinator service file not found, skipping..."
fi

# 3.5 Create Worktree Directories
echo -e "${GREEN} -> Creating worktree directories...${RESET}"
mkdir -p "$HOME/affordabot-worktrees"
mkdir -p "$HOME/prime-radiant-worktrees"
mkdir -p "$HOME/agent-skills-worktrees"

# 3.6 Configure Beads Merge Driver
echo -e "${GREEN} -> Configuring Beads merge driver...${RESET}"
if command -v bd >/dev/null 2>&1; then
    git config --global merge.beads.driver "bd merge %O %A %B %L %P" 2>/dev/null || true
    echo "   Beads merge driver configured globally"
else
    echo "   Beads CLI not found, skipping merge driver setup"
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
