# Technical Specification

---

## Entity Relationships

### The Mapping Chain

```
Beads Issue (bd-xyz)
    │
    ├─── creates ───► Git Worktree (~/affordabot-worktrees/bd-xyz/)
    │                      │
    │                      └─── isolated filesystem for this issue
    │
    ├─── tracks in ──► Slack Thread (#affordabot-agents, thread_ts)
    │                      │
    │                      └─── human-readable conversation
    │
    └─── executes via ─► OpenCode Session (ses_...)
                              │
                              └─── agent working directory = worktree
```

### Identity Model

| Entity | Identifier | Human Readable |
|--------|------------|----------------|
| Beads Issue | `bd-xyz` | Issue title |
| Git Worktree | `~/repo-worktrees/bd-xyz/` | Directory path |
| Slack Thread | `thread_ts` | Thread in channel |
| Slack Agent | `@epyc6` | Hostname-based |
| OpenCode Session | `ses_...` | (internal only) |

---

## Slack Routing

### Addressing

| Address | Meaning |
|---------|---------|
| `@epyc6` | New task on epyc6 |
| `@epyc6 repo:affordabot` | New task in affordabot repo |
| `@epyc6 session:ses_ABC123` | Resume specific session |
| `@macmini` | New task on macmini |
| `(no mention)` | Default to epyc6 |

### Extended Addressing Examples

| Message | Routes To | Display |
|---------|-----------|---------|
| `@epyc6 bd-xyz ...` | epyc6 | [epyc6] |
| `@macmini bd-abc ...` | macmini | [macmini] |
| `@jules bd-prs ...` | Google Cloud | [jules] |
| `bd-xyz do something` | epyc6 (default) | [epyc6] |
| `@epyc6 session:ses_ABC continue` | Resume session ABC | [epyc6] |

### Gateway Routing Logic

```python
def route_message(text):
    # Parse target host
    if "@macmini" in text:
        host = "macmini"
    elif "@epyc6" in text or no_mention(text):
        host = "epyc6"  # Default
    
    # Parse session (for resume)
    session_id = extract("session:", text)
    
    # Parse repo context
    repo = extract("repo:", text)
    
    # Route to OpenCode
    if session_id:
        return resume_session(host, session_id, text)
    else:
        return create_session(host, title=f"{repo or 'task'}-{uuid()}")
```

### Thread Ownership

```
Thread starts: @epyc6 bd-xyz implement auth
    └─── epyc6 owns this thread
    └─── All replies in thread go to epyc6
    └─── Session persists across messages
```

### Slack MCP vs Socket Mode

| Approach | Purpose | Direction |
|----------|---------|-----------|
| **Socket Mode** | Inbound: Slack → Agent | Receive tasks |
| **Slack MCP** | Outbound: Agent → Slack | Read context, post updates |

**Both are needed!**

---

## Git Worktrees

### Why Worktrees?

- **Filesystem isolation** - Each Beads issue gets isolated directory
- **Parallel work** - Multiple issues can run simultaneously
- **Branch per issue** - Clean git history

### Worktree Structure

```
~/affordabot/                    ← Main repo
├── .beads/
│   ├── issues.jsonl            ← Shared by all worktrees
│   └── beads.db                ← Shared database
│
~/affordabot-worktrees/
├── bd-xyz/                      ← Worktree for issue bd-xyz
│   ├── .beads → ../../../affordabot/.beads (shared)
│   ├── docs/bd-xyz/SPEC.md
│   └── (all source files)
├── bd-abc/                      ← Worktree for another issue
└── bd-def/
```

### Worktree Rules

| Rule | Why |
|------|-----|
| Use `BEADS_NO_DAEMON=1` | Daemon doesn't know which worktree |
| One branch per worktree | Git enforces this |
| Worktrees share `.beads/` | Issues visible across all |

### Implementation

```python
def ensure_worktree(repo_path: str, beads_id: str) -> str:
    """Create worktree for issue if not exists."""
    worktree_dir = f"{repo_path}-worktrees/{beads_id}"
    
    if not os.path.exists(worktree_dir):
        branch = f"feature-{beads_id}"
        subprocess.run([
            "git", "-C", repo_path, "worktree", "add",
            worktree_dir, "-b", branch
        ])
    
    return worktree_dir
```

---

## Beads Conflict Resolution

### The Problem

```
Orchestrator                    Agent (epyc6)
────────────                    ──────────────
bd create bd-xyz                
git push                        
                                git pull
                                bd update --status in_progress
                                git push
git pull                        
  └─── CONFLICT in issues.jsonl
```

### The Solution: beads-merge Driver

```bash
git config --global merge.beads.driver "bd merge %O %A %B %L %P"
```

Merge behavior:
- Same issue, different fields → merge both
- Same issue, same field → latest timestamp wins
- Different issues → include both

### Merge Driver Status

| Machine | Configured |
|---------|------------|
| epyc6 | ✅ |
| macmini | ✅ |
| homedesktop-wsl | ✅ |

---

## OpenCode Sessions

### Session API

| Endpoint | Purpose |
|----------|---------|
| `GET /session` | List all sessions |
| `GET /session/:id` | Get specific session |
| `POST /session` | Create new session (`{ parentID?, title? }`) |
| `POST /session/:id/fork` | Fork a session |
| `GET /session/:id/message` | Get all messages (for resume) |
| `POST /session/:id/message` | Send message (resume work) |

### Key Insight: Sessions ARE Resumable

Yes, you can work on Task A, switch to Task B, then resume Task A:

```
1. User: "@epyc6 start task A"
   → Session created: ses_ABC123
2. User: "@epyc6 start task B"  
   → New session: ses_DEF456
3. User: "@epyc6 continue session ses_ABC123"
   → GET /session/ses_ABC123/message (load context)
   → POST /session/ses_ABC123/message (continue work)
```

Sessions persist on disk. OpenCode maintains state.

### Parallel Work Model

```
epyc6 OpenCode Server (port 4105)
├── Session A: affordabot/feature-auth (active)
├── Session B: prime-radiant/fix-bug (paused)
├── Session C: llm-common/add-tests (active)
└── ... up to 10 parallel sessions
```

Each session can be in a different repo. **VM and repo are independent.**

### VM ≠ Repo (Critical Insight)

**Wrong assumption:**
```
#affordabot-agents → always routes to epyc6
#prime-radiant-agents → always routes to macmini
```

**Correct understanding:**
```
Any agent can work on ANY repo from ANY VM:
- epyc6 can work on affordabot, prime-radiant, llm-common
- macmini can work on same repos, different branches
```

**Implications:**
- Channel-based routing is **wrong** - repos don't map to VMs
- Hostname-based routing is **correct** - `@epyc6` means "use epyc6's compute"
- Repo/branch is **per-task**, not per-VM

### Session Lifecycle

```
1. Slack message: @epyc6 bd-xyz implement auth
2. Coordinator parses: host=epyc6, beads=bd-xyz
3. Coordinator creates worktree (if not exists):
   git worktree add ~/affordabot-worktrees/bd-xyz -b feature-bd-xyz
4. Coordinator creates OpenCode session:
   POST /session { title: "bd-xyz: implement auth" }
5. Coordinator sends prompt with cwd:
   POST /session/:id/message { cwd: "~/affordabot-worktrees/bd-xyz" }
6. Session works in worktree, updates Beads
7. Response posted to Slack thread
```

### Session Resume

```
Thread continues: "now add the logout feature"
    └─── Coordinator finds existing session for this thread
    └─── POST /session/:id/message (resumes context)
```

### Session Registry

```json
{
  "slack_threads": {
    "1704384000.123456": {
      "session_id": "ses_abc123",
      "beads_id": "bd-xyz",
      "worktree": "~/affordabot-worktrees/bd-xyz",
      "host": "epyc6"
    }
  }
}
```

---

## Complete Workflow Example

### 1. Spec Phase

```
Human: Let's spec out new auth for affordabot
Orchestrator: Creating exploration issue...
  → bd create "Spec: new auth approach" -t task
  → Created: bd-xyz
  → Worktree: ~/affordabot-worktrees/bd-xyz/
  → Docs: docs/bd-xyz/SPEC.md
[Iteration happens in docs, no code yet]
```

### 2. Assignment Phase

```
Human: @epyc6 bd-xyz implement this spec
Slack: Message in #affordabot-agents
  → Coordinator receives event
  → Parses: host=epyc6, beads=bd-xyz
  → Creates session in worktree
  → [epyc6]: Working on bd-xyz...
```

### 3. Execution Phase

```
OpenCode on epyc6:
  → Reads docs/bd-xyz/SPEC.md
  → Implements code in worktree
  → bd update bd-xyz --status in_progress
  → Commits to feature-bd-xyz branch
  → git push
```

### 4. Completion Phase

```
Human: @epyc6 bd-xyz looks good, create a PR
OpenCode:
  → gh pr create --title "bd-xyz: Auth implementation"
  → bd update bd-xyz --status closed
  → [epyc6]: ✅ PR created: #42
```

---

## Agent-to-Agent Communication

### Current (Missing)

```
Human → Slack → Coordinator → Agent
Agent → Slack → Human
```

### Required

```
Agent A → Slack → Agent B  (handoff)
Agent A → Beads → Agent B  (async)
```

### Solution

```
Agent A: Working on bd-xyz, needs help
         → bd update bd-xyz --add-label needs-macmini-help
         → Posts: "@macmini can you help with the build?"
         
Agent B: (via coordinator routing)
         → Picks up @macmini mention
         → Works in same worktree via Beads
```

**Gap:** Coordinator needs @mention in thread replies, not just new messages.
