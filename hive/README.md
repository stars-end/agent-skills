# Hive Mind

A distributed autonomous agent orchestration layer that dispatches AI agents to work on tasks across isolated worktrees.

## Overview

The Hive Mind is a task execution system that:
1. Polls for tasks labeled `hive-ready` in Beads
2. Creates isolated, ephemeral workspaces (pods) for each task
3. Spawns autonomous AI agents with proper context
4. Monitors and manages agent lifecycles

## Architecture

```
hive/
├── node/
│   ├── hive-queen.py      # The autonomous dispatcher (polls Beads, spawns agents)
│   └── hive-queen.service # systemd service definition for Queen Bee
├── orchestrator/
│   ├── dispatch.py        # Agent execution via systemd-run
│   ├── prompts.py         # System prompt generation and context preparation
│   ├── monitor.py         # Log tailing for active sessions
│   └── hive-status.py     # Swarm status dashboard
└── pods/
    └── create.sh          # Pod isolation engine (creates worktrees)
```

## Components

### Queen Bee (`node/hive-queen.py`)

The central dispatcher that:
- Polls Beads for issues labeled `hive-ready` every 30 seconds
- Auto-syncs with git to pull new tasks
- Creates pods with isolated git worktrees
- Prepares mission context and memory via Cass search
- Dispatches agents using systemd-run
- Updates Beads status with session IDs

### Orchestrator

- **dispatch.py**: Executes agents in background sessions using systemd-run
- **prompts.py**: Generates the "Golden Path" system prompt and prepares the briefcase (context files)
- **monitor.py**: Tails agent logs in real-time
- **hive-status.py**: Status dashboard showing active agents across local and remote nodes

### Isolation Engine (`pods/create.sh`)

Creates secure pod workspaces:
- Creates isolated git worktrees per task
- Installs safety hooks (git-safety-guard)
- Sets up context directories for mission/memory
- Configures proper permissions (700)

## Pod Structure

Each pod at `/tmp/pods/<session_id>/` contains:
```
/tmp/pods/<session_id>/
├── worktrees/          # Git worktrees for required repos
│   └── agent-skills/   # Per-repo worktree on branch hive/<session_id>/<repo>
├── context/            # Agent briefcase
│   ├── 00_MISSION.md   # Task description
│   └── 02_MEMORY.md    # Relevant context from Cass
├── logs/               # Agent execution logs
│   └── agent.log
└── state/              # Runtime state
```

## Usage

### Installing Queen Bee as a Service

```bash
# Link the service file
ln -s ~/agent-skills/hive/node/hive-queen.service ~/.config/systemd/user/

# Enable and start
systemctl --user daemon-reload
systemctl --user enable hive-queen
systemctl --user start hive-queen

# Check status
systemctl --user status hive-queen
```

### Checking Swarm Status

```bash
# Local status only
python3 ~/agent-skills/hive/orchestrator/hive-status.py

# Scan multiple nodes (MagicDNS hosts)
python3 ~/agent-skills/hive/orchestrator/hive-status.py --nodes runner-01,mac-mini
```

### Monitoring an Active Session

```bash
# Local pod
python3 ~/agent-skills/hive/orchestrator/monitor.py <session_id>

# Remote pod
python3 ~/agent-skills/hive/orchestrator/monitor.py <session_id> runner-01
```

## Agent Workflow

1. Queen Bee polls Beads for `hive-ready` tasks
2. Pod is created with isolated git worktrees
3. Mission context is fetched from Beads + memory from Cass
4. Agent is dispatched with a "Golden Path" system prompt
5. Agent executes: Understand -> Act -> Verify -> Commit
6. Bead status is updated with session label

## Safety Features

- Git worktrees provide complete isolation from main repo
- Safety hooks installed in each worktree (via git-safety-guard)
- Agents do NOT push changes (only commit locally)
- Pods have restricted permissions (700)
- Session IDs track all work back to original Bead

## Dependencies

- `bd` - Beads CLI for task management
- `cass` - Context search for memory retrieval
- `git` - Worktree creation and management
- `systemd` - Background agent execution
- `cc-glm` - Claude Code wrapper function
