---
name: jules-dispatch
description: |
  Dispatches work to Jules agents via the CLI. Automatically generates context-rich prompts from Beads issues and spawns async sessions. Use when user says "send to jules", "assign to jules", "dispatch task", or "run in cloud".
tags: [workflow, jules, cloud, automation, dx]
---

# Jules Dispatch Skill

**Purpose:** Automate the handoff of Beads issues to Jules agents using the `jules` CLI.

## Activation

**Triggers:**
- "assign this to jules"
- "dispatch bd-123 to jules"
- "start jules session for X"
- "run these in the cloud"

**User provides:** Issue IDs (bd-xyz) OR prompt text.

## Core Workflow

### 1. Context Generation (The "Rich Prompt")
Jules needs the same context guidance as Claude Code Web. We will reuse/adapt the `parallelize-cloud-work` prompt logic.

**Prompt Structure:**
```
TASK: {issue_title} ({issue_id})
CONTEXT:
- Repo: {repo_name}
- Branch: feature-{issue_id}-jules

🚨 INSTRUCTIONS:
1. INVOKE SKILLS: {context_skills}
2. EXPLORE: Check {files_of_interest}
3. PLAN: Don't reimplement existing logic.
4. EXECUTE:
   - Checkout branch feature-{issue_id}-jules
   - Commit with Feature-Key: {issue_id}
   - Push and create PR
```

### 2. Dispatch Logic
The skill will wrap the `jules remote new` command.

**Command Template:**
```bash
jules remote new \
  --repo . \
  --session "{RICH_PROMPT}"
```

### 3. Loop & Parallelize
If multiple issues are provided:
```bash
# pseudocode
for issue_id in provided_issues:
  prompt = generate_rich_prompt(issue_id)
  jules remote new --repo . --session "$prompt"
```

## Workflow

### 1. Execute Dispatch Script

```bash
# Dispatch single issue
python3 ~/agent-skills/scripts/jules-dispatch.py bd-123

# Dispatch multiple issues (parallel)
python3 ~/agent-skills/scripts/jules-dispatch.py bd-123 bd-124 bd-125
```

The script will:
1. Fetch issue details from Beads.
2. Auto-detect context skills based on keywords.
3. Generate a comprehensive prompt.
4. Run `jules remote new` to spawn the session.

### 2. Monitor Progress

```bash
# List active sessions
jules remote list --session

# Check for PRs
gh pr list --search "jules in:head"
```

## User Experience

**Input:**
`User: dispatch bd-105 to jules`

**Output:**
```
🚀 Dispatching bd-105 to Jules...
✅ Session started: jules-session-8f92a (Async)
   - Prompt includes context: context-database-schema
   - Branch: feature-bd-105-jules

Use `jules remote list --session` to track status.
```

## Integration with Beads
- **Pre-flight:** Ensure `beads export` is run and committed (so Jules sees the issue).
- **Post-flight:** The Jules agent should be instructed to update the Beads issue (e.g., set status to In Progress) if possible, or the user does it.

## Dependencies
- `jules` CLI installed and authenticated.
- `bd` CLI available.
