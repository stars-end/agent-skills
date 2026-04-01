---
name: dirty-repo-bootstrap
description: |
  Safe recovery procedure for dirty or WIP repositories. Standardizes
  snapshotting uncommitted work to a WIP branch before destructive operations.
---

# dirty-repo-bootstrap

## Description

Safe recovery procedure for dirty/WIP repositories. This skill provides a standardized workflow for:
- Snapshotting uncommitted work to a WIP branch
- Pushing the snapshot to origin for safety
- Handling Beads-tracked repositories correctly
- Recovering from repository corruption

**Non-negotiables:**
- Do NOT stash by default - snapshot to a branch and push
- Do NOT print secrets (bearer tokens, headers, etc.)
- Warning-only locally; CI can fail-loud

## When to Use This Skill

Use this skill when:
1. You have uncommitted changes and need to switch contexts
2. You want to save work-in-progress before destructive operations
3. You need to recover from a dirty/corrupted repository state
4. You're starting a new task and the repo has uncommitted changes

Do NOT use this skill if:
- The repository is already clean (`git status` shows no changes)
- You want to discard changes (use `git restore` instead)

## Usage

### Quick Recovery (Copy/Paste)

If you have uncommitted changes and need to snapshot them safely:

```bash
~/.agent/skills/dirty-repo-bootstrap/snapshot.sh
```

### Manual Recovery Flow

For manual control or custom branch names:

```bash
# 1. Check git status
git status

# 2. Create WIP branch with timestamp
git checkout -b wip/$(hostname)-$(date +%Y-%m-%d)-$(basename "$PWD")

# 3. If operating in canonical Beads repo, verify Beads health first
if [[ "$(git rev-parse --show-toplevel)" = "$HOME/bd" ]]; then
  beads-dolt dolt test --json
  beads-dolt status --json
fi

# 4. Add all changes and commit
git add -A
git commit -m "wip: snapshot before [describe your next task]"

# 5. Push WIP branch to origin
git push -u origin HEAD

# 6. Return to trunk (master by default)
git checkout master  # or main in some repos
git pull origin master
```

## WIP Branch Naming Convention

Use descriptive WIP branch names:

```
wip/<hostname>-<date>-<context>
```

Examples:
- `wip/epyc6-2025-12-13-agent-skills`
- `wip/macmini-2025-12-13-affordabot`
- `wip/codex-vm-2025-12-13-prime-radiant`

This naming convention:
- Identifies the machine/environment
- Timestamps the snapshot
- Describes the repository context
- Makes it easy to clean up old WIP branches later

## Beads Integration

**CRITICAL:** Beads mutations should run in canonical `~/bd`, not app repositories.

Safe flow:

```bash
# 1. If snapshotting ~/bd itself, verify Beads backend health
if [[ "$(git rev-parse --show-toplevel)" = "$HOME/bd" ]]; then
  beads-dolt dolt test --json
  beads-dolt status --json
fi

# 2. Then proceed with WIP snapshot
git add -A
git commit -m "wip: snapshot with Beads health verified"
git push -u origin HEAD
```

## Repository Corruption Recovery

If your repository appears corrupted or `git status` fails:

```bash
# 1. Verify basic git repository structure
git rev-parse --show-toplevel
# Should print the repo root path. If it fails, the .git directory is damaged.

# 2. Check for HEAD corruption
git log -1
# Should show the most recent commit. If it fails, HEAD is corrupted.

# 3. If this is ~/bd, verify Dolt backend connectivity
if [[ "$(git rev-parse --show-toplevel)" = "$HOME/bd" ]]; then
  beads-dolt dolt test --json || echo "Beads backend unreachable"
fi

# 4. If git is severely damaged, consider:
#    - Cloning fresh from origin
#    - Manually copying uncommitted work from backup
#    - Consulting git fsck output for recovery hints
git fsck --full
```

## Automation Script

The `snapshot.sh` script automates the safe WIP snapshot flow:

```bash
~/.agent/skills/dirty-repo-bootstrap/snapshot.sh [--branch-name <name>] [--message <msg>]
```

Options:
- `--branch-name <name>`: Custom WIP branch name (default: auto-generated)
- `--message <msg>`: Custom commit message (default: "wip: snapshot before next task")

The script:
1. Checks if the repo is dirty
2. Creates a WIP branch with timestamp
3. Detects canonical Beads repo and verifies Dolt health if needed
4. Commits all changes
5. Pushes to origin
6. Returns to the previous branch (or main/master)

Exit codes:
- `0`: Success (snapshot created and pushed)
- `1`: Repository is already clean (no snapshot needed)
- `2`: Git operation failed
- `3`: Beads health check failed (when snapshotting `~/bd`)

## Best Practices

### 1. Snapshot Early, Snapshot Often

Create WIP snapshots before:
- Starting a new feature or bug fix
- Running destructive git operations (rebase, reset, etc.)
- Switching to a different task mid-work
- Making experimental changes

### 2. Clean Up WIP Branches Regularly

WIP branches are temporary. After you've safely merged or abandoned the work:

```bash
# List all WIP branches
git branch -r | grep wip/

# Delete a WIP branch (local and remote)
git branch -d wip/epyc6-2025-12-13-agent-skills
git push origin --delete wip/epyc6-2025-12-13-agent-skills
```

### 3. Never Stash for Long-Term Storage

Git stash is good for temporary context switching (minutes to hours).

For longer-term WIP storage (hours to days):
- Use WIP branches (this skill)
- Push to origin for safety
- Stashes can be lost or forgotten

### 4. Include Context in Commit Messages

When creating WIP snapshots, include context about what you were working on:

```bash
git commit -m "wip: snapshot before implementing user authentication

- Added login form UI
- Started session management logic
- TODO: implement password hashing"
```

This helps you (and other agents) understand the WIP state when you return to it.

## Integration with Other Skills

This skill is referenced by:
- **mcp-doctor**: Checks that the skills mount is correct
- **skills-doctor**: Validates skill availability
- **beads-workflow**: May recommend this skill when detecting dirty repos

Use in combination with:
- **session-end**: Snapshot work before ending a coding session
- **sync-feature-branch**: For committing polished work (not WIP)
- **create-pull-request**: Requires clean repo state

## CI/CD Integration

For CI environments where you want strict enforcement:

```bash
# In .github/workflows/ci.yml or similar:
export MCP_DOCTOR_STRICT=1  # Fail builds if required MCPs missing
~/.agent/skills/mcp-doctor/check.sh

# Or fail if repo is dirty:
if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ Repository has uncommitted changes"
  exit 1
fi
```

In CI, you typically want to:
- Fail if the repo is dirty (prevents accidental commits)
- Skip the snapshot flow (CI runs on clean checkouts)

Locally, you want to:
- Warn if the repo is dirty
- Offer to run `snapshot.sh` to clean it up

## Troubleshooting

### "fatal: not a git repository"

Your current directory is not a git repository. Navigate to the repository root:

```bash
cd ~/agent-skills  # or your repo path
git status
```

### "error: failed to push some refs"

The WIP branch might already exist on origin with conflicting commits. Options:

1. Use a different branch name:
   ```bash
   git checkout -b wip/epyc6-2025-12-13-agent-skills-v2
   ```

2. Force push (DANGEROUS - only if you're sure):
   ```bash
   git push --force-with-lease origin HEAD
   ```

### "bd: command not found"

Beads CLI is not installed. If your repo doesn't use Beads, you can skip this check.

If your repo DOES use Beads, install it:
```bash
npm install -g @beadshq/beads-cli
```

### "bd dolt test" fails

The Beads backend service is unavailable or unhealthy. Try:

```bash
# Linux hosts
systemctl --user restart beads-dolt.service

# macOS host
launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt

# Re-test
beads-dolt dolt test --json && beads-dolt status --json
```

## Related Documentation

- [DX Bootstrap Contract](../DX_BOOTSTRAP_CONTRACT.md) - Session start requirements
- [mcp-doctor](../mcp-doctor/SKILL.md) - MCP server health checks
- [beads-workflow](../beads-workflow/SKILL.md) - Issue tracking integration
- [sync-feature-branch](../sync-feature-branch/SKILL.md) - Polished commit workflow

## Version History

- **v1.0.0** (2025-12-13): Initial implementation for bd-3871.15
  - Safe WIP snapshot workflow
  - Beads integration support
  - Repository corruption recovery guidance
  - Automation script (snapshot.sh)
