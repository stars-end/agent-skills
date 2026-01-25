# DX Skills Integration

Integration with the V3 DX workflow system.

---

## dx-hydrate.sh

### Current

- ✅ Installs OpenCode server service
- ✅ Configures systemd

### Missing

- [ ] Install slack-coordinator service
- [ ] Configure Slack tokens (prompt or environment)
- [ ] Configure Beads merge driver
- [ ] Set up Slack MCP in OpenCode config
- [ ] Create worktree directories

### Required Changes

```bash
# In dx-hydrate.sh

# Coordinator service
install_coordinator_service() {
    cp "$AGENT_SKILLS/systemd/slack-coordinator.service" \
       ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable slack-coordinator
}

# Slack MCP for OpenCode
configure_opencode_mcp() {
    mkdir -p ~/.config/opencode
    cat > ~/.config/opencode/opencode.json << 'EOF'
{
  "mcp": {
    "slack": {
      "type": "local",
      "command": ["npx", "-y", "slack-mcp-server@latest", "--transport", "stdio"],
      "enabled": true,
      "environment": {
        "SLACK_MCP_XOXB_TOKEN": "{env:SLACK_MCP_XOXB_TOKEN}",
        "SLACK_MCP_ADD_MESSAGE_TOOL": "true"
      }
    }
  }
}
EOF
}

# Beads merge driver
configure_beads_merge() {
    git config --global merge.beads.driver "bd merge %O %A %B %L %P"
}

# Worktree directories
create_worktree_dirs() {
    mkdir -p ~/affordabot-worktrees
    mkdir -p ~/prime-radiant-worktrees
}
```

---

## dx-check.sh

### Current

- ✅ Git status
- ✅ Beads CLI
- ✅ Railway shell

### Missing

- [ ] Coordinator running
- [ ] OpenCode health
- [ ] Active session count
- [ ] Worktree status

### Required Changes

```bash
# In dx-check.sh

check_coordinator() {
    if systemctl --user is-active slack-coordinator >/dev/null 2>&1; then
        echo "✅ Coordinator: running"
    else
        echo "❌ Coordinator: not running"
        return 1
    fi
}

check_opencode() {
    if curl -s http://localhost:4105/global/health | grep -q "healthy"; then
        echo "✅ OpenCode: healthy"
    else
        echo "❌ OpenCode: not healthy"
        return 1
    fi
}

check_sessions() {
    count=$(curl -s http://localhost:4105/session | jq 'length')
    echo "📊 Active sessions: $count"
}

check_worktrees() {
    wt_count=$(find ~/affordabot-worktrees -maxdepth 1 -type d | wc -l)
    echo "📁 Worktrees: $((wt_count - 1))"
}
```

---

## dx-doctor.sh

### Missing Entirely

Required diagnostics:

```bash
#!/usr/bin/env bash
# dx-doctor.sh - Diagnose and repair coordinator issues

diagnose_slack() {
    echo "=== Slack Connection ==="
    if [[ -z "$SLACK_BOT_TOKEN" ]]; then
        echo "❌ SLACK_BOT_TOKEN not set"
        echo "   Fix: export SLACK_BOT_TOKEN=xoxb-..."
    else
        echo "✅ SLACK_BOT_TOKEN set"
    fi
    
    if [[ -z "$SLACK_APP_TOKEN" ]]; then
        echo "❌ SLACK_APP_TOKEN not set"
        echo "   Fix: export SLACK_APP_TOKEN=xapp-..."
    else
        echo "✅ SLACK_APP_TOKEN set"
    fi
}

diagnose_opencode() {
    echo "=== OpenCode Sessions ==="
    sessions=$(curl -s http://localhost:4105/session)
    echo "$sessions" | jq -r '.[] | "  \(.id): \(.title)"'
}

diagnose_beads() {
    echo "=== Beads Sync ==="
    cd ~/affordabot
    if git diff --name-only | grep -q ".beads/"; then
        echo "⚠️  Uncommitted Beads changes"
        echo "   Fix: bd sync && git push"
    else
        echo "✅ Beads in sync"
    fi
}

repair_common() {
    echo "=== Attempting Repairs ==="
    
    # Restart coordinator
    systemctl --user restart slack-coordinator
    
    # Sync Beads
    cd ~/affordabot && bd sync && git push
    
    echo "✅ Repairs complete"
}
```

---

## dx-deploy.sh

### Missing Entirely

Required for multi-VM deployment:

```bash
#!/usr/bin/env bash
# dx-deploy.sh - Deploy coordinator to all VMs

TARGET_VMS="${TARGET_VMS:-epyc6 macmini}"

for vm in $TARGET_VMS; do
    echo "=== Deploying to $vm ==="
    
    # Pull latest code
    ssh $vm 'cd ~/agent-skills && git pull origin master'
    
    # Run hydration
    ssh $vm '~/agent-skills/scripts/dx-hydrate.sh'
    
    # Restart services
    ssh $vm 'systemctl --user restart opencode'
    ssh $vm 'systemctl --user restart slack-coordinator'
    
    # Verify
    ssh $vm 'dx-check'
done

echo "=== Deployment Complete ==="
```

---

## Feature Lifecycle Skills

### start-feature

```bash
# Should also create worktree
start-feature bd-xyz
→ git worktree add ~/affordabot-worktrees/bd-xyz -b feature-bd-xyz
→ cd ~/affordabot-worktrees/bd-xyz
```

### sync-feature

```bash
# Works in worktree
sync-feature "implemented auth"
→ BEADS_NO_DAEMON=1 bd update bd-xyz --notes "..."
→ git commit -am "..."
→ git push
```

### finish-feature

```bash
# Cleanup worktree
finish-feature
→ gh pr create
→ git worktree remove ~/affordabot-worktrees/bd-xyz
→ bd update bd-xyz --status closed
```

---

## Environment Variables

| Variable | Required | Source |
|----------|----------|--------|
| `SLACK_BOT_TOKEN` | ✅ | ~/.zshenv |
| `SLACK_APP_TOKEN` | ✅ | ~/.zshenv |
| `SLACK_MCP_XOXB_TOKEN` | ✅ | ~/.zshenv |
| `SLACK_MCP_ADD_MESSAGE_TOOL` | ✅ | ~/.zshenv |
| `BEADS_NO_DAEMON` | Worktrees | Set per-worktree |
| `OPENCODE_URL` | Optional | Default: localhost:4105 |
