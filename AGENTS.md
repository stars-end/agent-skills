# AGENTS.md — Agent Skills V3 DX

**Start Here**
1. **Initialize**: `source ~/.bashrc && dx-check || curl -fsSL https://raw.githubusercontent.com/stars-end/agent-skills/master/scripts/dx-hydrate.sh | bash`
2. **Check Environment**: `dx-check` checks git, Beads, and Skills.

**Core Tools**:
- **Beads**: Issue tracking. Use `bd` CLI.
- **Skills**: Automated workflows.

**Daily Workflow**:
1. `start-feature bd-xxx` - Start work.
2. Code...
3. `sync-feature "message"` - Save work.
4. `finish-feature` - Verify & PR.

---

## Skills (agentskills.io Format)

Skills are stored in `~/agent-skills/*/SKILL.md` using the [agentskills.io](https://agentskills.io) open standard.

**Agent Skill Discovery:**

| Agent | Discovery Method |
|-------|------------------|
| Claude Code | Native `/skill <name>` command |
| OpenCode | Native `skill <name>` tool |
| Codex CLI | Native skill loading |
| Antigravity | universal-skills MCP → `load_skill()` |
| Gemini CLI | universal-skills MCP → `load_skill()` |

**Available Skills:**
- `multi-agent-dispatch` - Cross-VM task dispatch
- `beads-workflow` - Issue tracking
- `sync-feature-branch` - Git workflows
- `fix-pr-feedback` - PR iteration

---



## Multi-Agent Dispatch

**When to use**: Tasks needing specific VMs (GPU work → epyc6, macOS → macmini), parallel execution, or status notifications.

```bash
dx-dispatch epyc6 "Run make test in ~/affordabot"
dx-dispatch macmini "Build iOS app"
dx-dispatch --list   # Check VM status
```

**Add Slack notifications** to long tasks:
```
After completing, use slack_conversations_add_message 
to post summary to channel C09MQGMFKDE.
```

📖 **Full guide**: [docs/MULTI_AGENT_COMMS.md](docs/MULTI_AGENT_COMMS.md)



## Claude CLI: Always Use `cc-glm`

**`cc-glm`** is a pre-configured Claude Code alias (defined in `~/.zshrc`) that:
- Uses the correct model configuration
- Handles authentication automatically
- Supports all standard `claude` flags

```bash
# Interactive session
cc-glm

# Non-interactive (one-shot)
cc-glm -p "Your prompt here"

# With output format
cc-glm -p "Prompt" --output-format text

# Resume session
cc-glm --resume <session-id>
```

**RULE:** Always use `cc-glm` instead of raw `claude` command.

---

## Slack MCP Integration

Agents have native Slack access via MCP tools:
- `conversations_add_message` - Post to channels/threads
- `conversations_history` - Read channel history
- `conversations_replies` - Read thread replies

**Config:** Set in `~/.claude.json` → `mcpServers.slack`

**Token Setup (in `~/.zshenv` for non-interactive shells):**
```bash
# For bot tokens (xoxb-...)
export SLACK_MCP_XOXB_TOKEN="xoxb-..."
export SLACK_MCP_ADD_MESSAGE_TOOL=true

# For user tokens (xoxp-...)
export SLACK_MCP_XOXP_TOKEN="xoxp-..."
```

**Important:** After adding bot, invite it to channels: `/invite @YourBotName`

**Test (use explicit session ID when other sessions running):**
```bash
cc-glm --session-id $(uuidgen) -p "Use conversations_add_message to post 'Test' to #social"
```

---

**Repo Context: Skills Registry**
- **Purpose**: Central store for all agent skills, scripts, and configurations.
- **Rules**:
  - Scripts must be idempotent.
  - `dx-hydrate.sh` is the single source of truth for setup.


## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
