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

# 2. Setup skills plane (canonical: ~/.agents/skills)
echo -e "${GREEN} -> Setting up skills plane (~/.agents/skills)...${RESET}"
mkdir -p "$HOME/.agents/skills"
if [[ -x "$AGENTS_ROOT/scripts/dx-agents-skills-install.sh" ]]; then
  "$AGENTS_ROOT/scripts/dx-agents-skills-install.sh" --apply >/dev/null 2>&1 || true
elif [[ -x "$AGENTS_ROOT/scripts/dx-codex-skills-install.sh" ]]; then
  # Backwards-compatible fallback name.
  "$AGENTS_ROOT/scripts/dx-codex-skills-install.sh" --apply >/dev/null 2>&1 || true
fi

# Legacy mount (kept for older tooling/scripts; not used by Codex skills discovery).
echo -e "${GREEN} -> Setting up legacy skills mount (~/.agent/skills)...${RESET}"
mkdir -p "$HOME/.agent"
ln -sfn "$AGENTS_ROOT" "$HOME/.agent/skills"

# 3. Install canonical executables in ~/bin
echo -e "${GREEN} -> Ensuring ~/bin tools...${RESET}"
"$AGENTS_ROOT/scripts/dx-ensure-bins.sh" >/dev/null 2>&1 || true

# 3.0 Auto-checkpoint: REMOVED in V8 (conflicts with canonical pre-commit hooks)
# See bd-xpnr for deprecation rationale.

# 3.0 Ensure ru is present (sync control plane)
if ! command -v ru >/dev/null 2>&1; then
  echo -e "${GREEN} -> Installing ru (repo_updater)...${RESET}"
  "$AGENTS_ROOT/scripts/install-ru.sh" >/dev/null 2>&1 || true
fi

# 3.1 Slack MCP (OPTIONAL)
echo -e "${GREEN} -> Slack MCP is optional (not configured by default)...${RESET}"

# 3.2 Install OpenCode (Systemd) — OPTIONAL coordinator stack
echo -e "${GREEN} -> Installing OpenCode systemd service (optional)...${RESET}"
mkdir -p "$HOME/.config/systemd/user"
if [ -f "$AGENTS_ROOT/systemd/opencode.service" ]; then
    cp "$AGENTS_ROOT/systemd/opencode.service" "$HOME/.config/systemd/user/"

    # Ensure scoped env file exists (safe to copy template; op run resolves op:// at runtime).
    mkdir -p "$HOME/.config/opencode"
    if [ ! -f "$HOME/.config/opencode/.env" ] && [ -f "$AGENTS_ROOT/scripts/env/opencode.env.template" ]; then
        cp "$AGENTS_ROOT/scripts/env/opencode.env.template" "$HOME/.config/opencode/.env"
        chmod 600 "$HOME/.config/opencode/.env" 2>/dev/null || true
    fi

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable opencode 2>/dev/null || true
    echo "   OpenCode service installed. Start with: systemctl --user start opencode"
else
    echo "   OpenCode service file not found, skipping..."
fi

# 3.3 Slack Coordinator: REMOVED in V8 (replaced by openclawd + cron)
# See bd-d25k for deprecation rationale.

# 3.5 Create Worktree Directories
echo -e "${GREEN} -> Creating worktree directories...${RESET}"
mkdir -p "$HOME/affordabot-worktrees"
mkdir -p "$HOME/prime-radiant-worktrees"
mkdir -p "$HOME/agent-skills-worktrees"
mkdir -p "$HOME/.dx-archives"

# 3.6 Install/verify versioned git hooks (V8.1)
echo -e "${GREEN} -> Bootstrapping versioned git hooks (.githooks + core.hooksPath)...${RESET}"
if [[ -x "$AGENTS_ROOT/scripts/dx-git-hooks-bootstrap.sh" ]]; then
    "$AGENTS_ROOT/scripts/dx-git-hooks-bootstrap.sh" 2>/dev/null || true
fi

# 3.7 Initialize HEARTBEAT.md (V8 status file for openclawd)
echo -e "${GREEN} -> Initializing HEARTBEAT.md...${RESET}"
mkdir -p "$HOME/.dx-state"
if [ ! -f "$HOME/.dx-state/HEARTBEAT.md" ]; then
    if [ -f "$AGENTS_ROOT/docs/HEARTBEAT.md.template" ]; then
        cp "$AGENTS_ROOT/docs/HEARTBEAT.md.template" "$HOME/.dx-state/HEARTBEAT.md"
        echo "   Copied HEARTBEAT.md template to ~/.dx-state/"
    fi
else
    echo "   HEARTBEAT.md already exists, skipping"
fi

# 3.8 Install V8 cron schedule (idempotent)
echo -e "${GREEN} -> Installing V8 cron schedule...${RESET}"
remove_wrapper_job_entries() {
    local job_name="$1"
    local script_name="$2"
    local current_cron updated_cron
    current_cron="$(crontab -l 2>/dev/null || true)"

    updated_cron="$(
        printf '%s\n' "$current_cron" | awk -v job="$job_name" -v script="$script_name" '
            /^[[:space:]]*#/ { print; next }
            /^[[:space:]]*$/ { print; next }
            {
                if (index($0, "dx-job-wrapper.sh") > 0 &&
                    index($0, " " job " -- ") > 0 &&
                    index($0, script) > 0) {
                    next
                }
                print
            }
        '
    )"

    if [[ "$updated_cron" != "$current_cron" ]]; then
        printf '%s\n' "$updated_cron" | crontab -
        echo "   Pruned duplicate cron entries for: $job_name ($script_name)"
    fi
}

remove_v8_marker_variants() {
    local marker="$1"
    local current_cron updated_cron
    current_cron="$(crontab -l 2>/dev/null || true)"

    updated_cron="$(
        printf '%s\n' "$current_cron" | awk -v marker="$marker" '
            {
                if ($0 ~ "^# " marker "([[:space:]].*)?$") {
                    next
                }
                print
            }
        '
    )"

    if [[ "$updated_cron" != "$current_cron" ]]; then
        printf '%s\n' "$updated_cron" | crontab -
        echo "   Removed stale marker variants for: $marker"
    fi
}

install_cron_entry() {
    local marker="$1"
    local entry="$2"
    local current_cron
    current_cron="$(crontab -l 2>/dev/null || true)"

    if printf '%s\n' "$current_cron" | grep -qF "# $marker"; then
        if printf '%s\n' "$current_cron" | grep -qF "$entry"; then
            echo "   Cron already installed: $marker"
            return
        fi

        local updated_cron
        updated_cron="$(
            printf '%s\n' "$current_cron" | awk -v marker="$marker" '
                BEGIN { skip_next=0 }
                skip_next { skip_next=0; next }
                $0 == "# " marker { skip_next=1; next }
                { print }
            '
        )"
        {
            printf '%s\n' "$updated_cron"
            echo ""
            echo "# $marker"
            echo "$entry"
        } | crontab -
        echo "   Updated cron: $marker"
    else
        {
            printf '%s\n' "$current_cron"
            echo ""
            echo "# $marker"
            echo "$entry"
        } | crontab -
        echo "   Added cron: $marker"
    fi
}

WRAPPER="$AGENTS_ROOT/scripts/dx-job-wrapper.sh"

# Detect bash path (macOS Homebrew vs Linux)
if [[ -x /opt/homebrew/bin/bash ]]; then
    BASH_PATH="/opt/homebrew/bin/bash"
elif [[ -x /usr/bin/bash ]]; then
    BASH_PATH="/usr/bin/bash"
else
    BASH_PATH="/bin/bash"
fi

# Ensure log directory exists
mkdir -p "$HOME/logs/dx"

# Remove non-canonical duplicate lines before (re)installing V8 marker entries.
remove_wrapper_job_entries "canonical-evacuate" "canonical-evacuate-active.sh"
remove_wrapper_job_entries "canonical-sync" "canonical-sync-v8.sh"
remove_wrapper_job_entries "worktree-push" "worktree-push.sh"
remove_wrapper_job_entries "worktree-gc" "worktree-gc-v8.sh"
remove_wrapper_job_entries "queue-enforcer" "queue-hygiene-enforcer.sh"
remove_wrapper_job_entries "beads-health" "beads-health-alert.sh"
remove_v8_marker_variants "V8.3.x: Canonical Enforcer - Active Hours (5am-5pm PT)"
remove_v8_marker_variants "V8: canonical-evacuate-active-15m"
remove_v8_marker_variants "V8: canonical-evacuate-active-1700"
remove_v8_marker_variants "V8: canonical-sync"
remove_v8_marker_variants "V8: worktree-push"
remove_v8_marker_variants "V8: worktree-gc"
remove_v8_marker_variants "V8: queue-hygiene-enforcer"
remove_v8_marker_variants "V8: beads-health"

install_cron_entry "V8: canonical-evacuate-active-15m" \
    "*/15 5-16 * * * TZ=America/Los_Angeles $BASH_PATH $WRAPPER canonical-evacuate -- $AGENTS_ROOT/scripts/canonical-evacuate-active.sh >> $HOME/logs/dx/canonical-evacuate.log 2>&1"

install_cron_entry "V8: canonical-evacuate-active-1700" \
    "0 17 * * * TZ=America/Los_Angeles $BASH_PATH $WRAPPER canonical-evacuate -- $AGENTS_ROOT/scripts/canonical-evacuate-active.sh >> $HOME/logs/dx/canonical-evacuate.log 2>&1"

install_cron_entry "V8: canonical-sync" \
    "5 3 * * * $BASH_PATH $WRAPPER canonical-sync -- $AGENTS_ROOT/scripts/canonical-sync-v8.sh >> $HOME/logs/dx/canonical-sync.log 2>&1"

install_cron_entry "V8: worktree-push" \
    "15 3 * * * $BASH_PATH $WRAPPER worktree-push -- $AGENTS_ROOT/scripts/worktree-push.sh >> $HOME/logs/dx/worktree-push.log 2>&1"

install_cron_entry "V8: worktree-gc" \
    "0 * * * * $BASH_PATH $WRAPPER worktree-gc -- $AGENTS_ROOT/scripts/worktree-gc-v8.sh >> $HOME/logs/dx/worktree-gc.log 2>&1"

install_cron_entry "V8: queue-hygiene-enforcer" \
    "0 */4 * * * DX_CONTROLLER=\${DX_CONTROLLER:-0} $BASH_PATH $WRAPPER queue-enforcer -- $AGENTS_ROOT/scripts/queue-hygiene-enforcer.sh >> $HOME/logs/dx/queue-enforcer.log 2>&1"

# 3.6 Beads health alert (Hub-only: epyc12) with stateful DX job alerts.
if [[ "$(hostname -s)" == "epyc12" ]]; then
    install_cron_entry "V8: beads-health" \
        "*/10 * * * * DX_ALERTS_CHANNEL_ID=\${DX_ALERTS_CHANNEL_ID:-C0AEC54RZ6V} $BASH_PATH $WRAPPER beads-health -- $AGENTS_ROOT/scripts/dx-beads-health-alert.sh >> $HOME/logs/dx/beads-health-alert.log 2>&1"
fi

# 3.9 macOS legacy launchd policy guard (V8.6)
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo -e "${GREEN} -> Enforcing macOS launchd policy (disable legacy io.agentskills.ru)...${RESET}"
    LEGACY_LABEL="io.agentskills.ru"
    LEGACY_PLIST="$HOME/Library/LaunchAgents/${LEGACY_LABEL}.plist"
    USER_DOMAIN="gui/$(id -u)"

    launchctl bootout "${USER_DOMAIN}/${LEGACY_LABEL}" >/dev/null 2>&1 || true
    launchctl disable "${USER_DOMAIN}/${LEGACY_LABEL}" >/dev/null 2>&1 || true

    if [[ -f "$LEGACY_PLIST" ]]; then
        mkdir -p "$HOME/.v7-quarantine"
        TS="$(date -u +%Y%m%dT%H%M%SZ)"
        mv "$LEGACY_PLIST" "$HOME/.v7-quarantine/${LEGACY_LABEL}.${TS}.plist" 2>/dev/null || true
        echo "   Quarantined legacy LaunchAgent plist: $LEGACY_LABEL"
    fi
fi

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

# 5. Safety Guard (Canonical): DCG
echo -e "${GREEN} -> Safety Guard: DCG (canonical)...${RESET}"
if command -v dcg >/dev/null 2>&1; then
    echo "   ✅ dcg installed"
else
    echo "   ⚠️  dcg not found (install per dcg-safety/SKILL.md)"
fi

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
            echo "export BEADS_IGNORE_REPO_MISMATCH=1" >> "$RC_FILE"
            
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
