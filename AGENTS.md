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
**Env vars:** `SLACK_MCP_XOXP_TOKEN`, `SLACK_MCP_ADD_MESSAGE_TOOL=true`

**Test:**
```bash
cc-glm -p "Use conversations_add_message to post 'Test' to #social"
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
