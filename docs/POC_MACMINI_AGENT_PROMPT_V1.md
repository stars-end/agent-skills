# macmini POC — Standard Agent Prompt (Claude Code + Antigravity) — V1

**Repo:** `agent-skills`  
**Host:** `macmini` (local-only POC)  
**Beads epic:** `bd-fleet-v5-hardening.1.10`  
**Agent run tasks:**
- Claude Code: `bd-fleet-v5-hardening.1.10.6`
- Antigravity: `bd-fleet-v5-hardening.1.10.7`

---

## Mission

Prove the V5/v6 workflow is usable by real agents (Claude Code + Antigravity) with low founder cognitive load:
- Canonical clones stay clean (no work on `~/agent-skills`)
- Work happens only in a worktree under `/tmp/agents/...`
- Beads uses external DB (`BEADS_DIR=~/bd/.beads`) and runs in direct mode (`--no-daemon` / `BEADS_NO_DAEMON=1`)
- Work is pushed and a **draft PR** is created (no lost work)

---

## Hard Rules (must follow)

1) **Do not commit in canonical repos.** If you are in `~/agent-skills`, stop and create a worktree.
2) **Do not create nested git repos** (no `git init` inside this repo).
3) **Use Beads for tracking**: update your assigned Beads task with outcome + links.
4) **Push your branch** and create a **draft PR** before ending.

---

## Step-by-step (do exactly this)

### 0) Preflight

Run:
```bash
echo "BEADS_DIR=$BEADS_DIR"
echo "BEADS_NO_DAEMON=$BEADS_NO_DAEMON"
dx-check
```

If `BEADS_NO_DAEMON` is empty, set it for this session:
```bash
export BEADS_NO_DAEMON=1
```

### 1) Claim your Beads task

Pick the correct ID for your tool:
- Claude Code: `bd-fleet-v5-hardening.1.10.6`
- Antigravity: `bd-fleet-v5-hardening.1.10.7`

Then:
```bash
bd --no-daemon update <ID> --status in_progress
```

### 2) Create a worktree (required)

```bash
WT=$(dx-worktree create <ID> agent-skills)
echo "$WT"
cd "$WT"
pwd
```

Confirm `pwd` starts with `/tmp/agents/`. If not, stop.

### 3) Make a small, reviewable change

Create a single file:
`docs/poc_runs/POC_RUN_<ID>.md`

Contents must include:
- Tool name (Claude Code or Antigravity)
- Timestamp (local)
- `git rev-parse --abbrev-ref HEAD`
- `git rev-parse HEAD`
- 3 bullets: what you did, what was confusing, what to improve

### 4) Commit + push + draft PR

```bash
git status --porcelain
git add docs/poc_runs/POC_RUN_<ID>.md
git commit -m "poc(macmini): record agent run (<ID>)"
git push -u origin HEAD
```

Create a draft PR:
```bash
gh pr create --draft \\
  --title "poc(macmini): agent run (<ID>)" \\
  --body "POC run for <ID>.\\n\\n- Worktree: $WT\\n- Beads: <ID>\\n"
```

### 5) Update Beads with results + links

Copy:
- PR URL (`gh pr view --json url -q .url`)
- Branch name (`git rev-parse --abbrev-ref HEAD`)
- Commit SHA (`git rev-parse HEAD`)

Then:
```bash
bd --no-daemon update <ID> --notes "PR: <url>\nBranch: <branch>\nSHA: <sha>\nNotes: <what worked/failed>"
bd --no-daemon sync
```

### 6) Validate canonicals stayed clean

```bash
cd ~/agent-skills
git status --porcelain
dx-check
```

Expected:
- `git status` is empty
- `dx-check` is “SYSTEM READY” (warnings OK)

---

## Stop Conditions (escalate instead of fighting)

If you hit any of these, stop and report in your Beads task notes:
- `dx-worktree` fails
- `git push` fails repeatedly
- hooks block you and you can’t proceed
- you are unsure whether you are in a worktree vs canonical

