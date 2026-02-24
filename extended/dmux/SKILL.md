---
name: dmux
description: |
  Parallel AI coding agents with tmux and git worktrees. Run multiple Claude Code, Codex, or OpenCode agents
  in isolated worktrees side-by-side. Each agent gets its own branch and working directory.
  Use when running multiple coding tasks in parallel, A/B testing agents, or managing multi-agent workflows.
  Keywords: dmux, parallel agents, tmux, worktree, claude code, codex, opencode, multi-agent
tags: [agents, tmux, worktree, parallel, ai-coding]
allowed-tools:
  - Bash(dmux:*)
  - Bash(git worktree:*)
  - Bash(tmux:*)
---

# dmux - Parallel AI Coding Agents

Manage multiple AI coding agents in isolated git worktrees. Branch, develop, and merge — all in parallel.

## Installation

```bash
npm install -g dmux
```

## Quick Start

```bash
cd /path/to/your/project
dmux
```

Press `n` to create a new pane, type a prompt, pick an agent, and dmux handles the rest — worktree, branch, and agent launch.

## Core Concepts

### Worktree Isolation

Each pane is a full working copy with its own branch:
- No conflicts between agents
- Clean separation of work
- Easy experimentation and rollback

```
main-project/              # Original repository
├── .git/                  # Git directory
├── src/                   # Your code
└── .dmux/                 # dmux data directory (gitignored)
    ├── dmux.config.json   # Configuration file
    └── worktrees/         # All worktrees for this project
        ├── fix-bug/       # Worktree for "fix bug" pane
        └── add-feature/   # Worktree for "add feature" pane
```

### Supported Agents

- **Claude Code** (`claude`) - Anthropic's coding agent
- **Codex** (`codex`) - OpenAI's coding agent
- **OpenCode** (`opencode`) - Open source alternative

### AI-Powered Features

- **Slug generation** - Converts prompts to branch names
- **Commit message generation** - Analyzes git diff for semantic commits
- **A/B launches** - Run two agents on the same prompt side-by-side

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `n` | New pane (worktree + agent) |
| `t` | New terminal pane |
| `j` / `Enter` | Jump to pane |
| `m` | Merge pane to main |
| `x` | Close pane |
| `p` | New pane in another project |
| `s` | Settings |
| `q` | Quit |

## Hooks System

dmux supports lifecycle hooks in `.dmux-hooks/` directory:

### Available Hooks

| Hook | When | Common Use Cases |
|------|------|------------------|
| `before_pane_create` | Before pane creation | Validation, pre-flight checks |
| `worktree_created` | After full setup | Install deps, copy configs |
| `before_pane_close` | Before closing | Save state, backup work |
| `pre_merge` | Before merge | Run tests, create backups |
| `post_merge` | After merge | Deploy, close issues, notify |

### Example Hook: Install Dependencies

```bash
#!/bin/bash
# .dmux-hooks/worktree_created

cd "$DMUX_WORKTREE_PATH"

if [ -f "pnpm-lock.yaml" ]; then
  pnpm install --prefer-offline &
elif [ -f "package-lock.json" ]; then
  npm install &
elif [ -f "requirements.txt" ]; then
  pip install -r requirements.txt &
fi
```

### Environment Variables (available in hooks)

```bash
DMUX_ROOT="/path/to/project"           # Project root directory
DMUX_PANE_ID="dmux-1234567890"         # dmux pane identifier
DMUX_SLUG="fix-auth-bug"               # Branch/worktree name
DMUX_PROMPT="Fix authentication bug"   # User's prompt
DMUX_AGENT="claude"                    # Agent type
DMUX_WORKTREE_PATH="/path/.dmux/worktrees/fix-auth-bug"
DMUX_TARGET_BRANCH="main"              # For merge hooks
```

## HTTP API

dmux exposes an HTTP API for programmatic control:

```bash
# List panes
curl http://localhost:3142/api/panes

# Create new pane
curl -X POST http://localhost:3142/api/panes \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Add tests", "agent": "claude"}'

# Send keystrokes
curl -X POST http://localhost:3142/api/keys/dmux-123 \
  -H "Content-Type: application/json" \
  -d '{"keys": ["Enter"]}'
```

## Action System

dmux uses a standardized action system that works across TUI, Web, and API:

| Action | Description |
|--------|-------------|
| `VIEW` | Jump to pane |
| `CLOSE` | Close pane |
| `MERGE` | Merge worktree to main |
| `RENAME` | Rename pane |
| `RUN_TEST` | Run tests via hook |
| `RUN_DEV` | Start dev server via hook |
| `TOGGLE_AUTOPILOT` | Auto-accept agent options |

## Settings

- **Global**: `~/.dmux.global.json`
- **Project**: `.dmux/settings.json`

Key settings:
- `enableAutopilotByDefault` - Auto-enable autopilot for new panes
- `defaultAgent` - Default agent ('claude' | 'opencode' | 'codex')

## Requirements

- tmux 3.0+
- Node.js 18+
- Git 2.20+
- At least one agent: Claude Code, Codex, or OpenCode
- OpenRouter API key (optional, for AI branch names)

## Integration with DX Worktrees

dmux complements our `worktree-workflow` skill:

| Feature | dmux | dx-worktree |
|---------|------|-------------|
| UI | tmux TUI | CLI only |
| Agents | Auto-launch | Manual |
| Hooks | Extensive | Minimal |
| Best for | Parallel experiments | Task isolation |

**Recommendation**: Use dmux for interactive multi-agent development, dx-worktree for scripted/CI workflows.

## Common Patterns

### A/B Testing Agents

1. Press `n` with prompt "Implement feature X"
2. Select Claude Code
3. Press `n` again with same prompt
4. Select Codex
5. Compare outputs in side-by-side panes

### Batch Task Creation

```bash
for task in "fix auth" "add tests" "refactor api"; do
  curl -X POST http://localhost:3142/api/panes \
    -H "Content-Type: application/json" \
    -d "{\"prompt\": \"$task\", \"agent\": \"claude\"}"
done
```

### Post-Merge Deployment Hook

```bash
#!/bin/bash
# .dmux-hooks/post_merge

cd "$DMUX_ROOT"

if [ "$DMUX_TARGET_BRANCH" = "main" ]; then
  git push origin main
  # Trigger deployment
  curl -X POST https://api.vercel.com/v1/deployments \
    -H "Authorization: Bearer $VERCEL_TOKEN"
fi
```

## Troubleshooting

```bash
# List sessions
tmux list-sessions

# View config
cat .dmux/dmux.config.json

# Check running processes
ps aux | grep dmux

# Refresh screen
Ctrl+L or tmux refresh-client
```

## Resources

- Documentation: https://dmux.ai
- GitHub: https://github.com/formkit/dmux
- API Reference: See API.md in dmux repo
