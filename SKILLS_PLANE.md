# Skills Plane: Shared Profiles + Shared Core

## Overview

The "skills plane" is the canonical infrastructure that enables skill discovery and management across all agent tools (Claude Code, Codex CLI, Gemini/Antigravity, etc.) on a host.

This document defines:
- **bd-3871.5**: Shared profiles architecture
- **bd-3871.6**: Shared core invariants
- **bd-3871.15**: Dirty repo recovery (see [dirty-repo-bootstrap](./dirty-repo-bootstrap/SKILL.md))

## The Canonical Invariant

**All agent tools on a host MUST share the same skills repository through a canonical mount point.**

```
~/.agent/skills -> ~/agent-skills (symlink or exact copy)
```

This invariant ensures:
1. **Consistency**: All agents see the same skills
2. **Discoverability**: Direct filesystem access enables skill discovery
3. **Single source of truth**: Skills are managed in one place (`~/agent-skills`)
4. **Git integration**: Skills are version-controlled and can be updated via git

## Architecture

### 1. Repository: `~/agent-skills`

The primary skills repository, cloned from `stars-end/agent-skills`:

```bash
git clone https://github.com/stars-end/agent-skills.git ~/agent-skills
```

Contains:
- Individual skill directories (e.g., `mcp-doctor/`, `beads-workflow/`)
- Each skill has a `SKILL.md` and optional scripts
- Shared documentation and helper scripts
- Git-tracked for versioning and updates

### 2. Mount Point: `~/.agent/skills`

The canonical mount point where all agent tools look for skills:

```bash
ln -sfn ~/agent-skills ~/.agent/skills
```

This is a symlink (preferred) or exact copy (fallback) that points to `~/agent-skills`.

## Discovery Precedence

When an agent tool looks for skills, the discovery order is:

1. **Direct filesystem** (`~/.agent/skills/`)
   - Primary method
   - Manual skill invocation
   - Used by helper scripts

2. **Repo-specific skills** (`.claude/`, `.skills/`, etc.)
   - Lowest precedence
   - Project-specific overrides
   - Not shared across projects

## Setup Instructions

### Step 1: Clone agent-skills

```bash
# Clone the canonical skills repository
git clone https://github.com/stars-end/agent-skills.git ~/agent-skills
```

Or use the helper script:

```bash
~/agent-skills/scripts/ensure_agent_skills_mount.sh
```

### Step 2: Create Mount Point

```bash
# Create .agent directory if needed
mkdir -p ~/.agent

# Create symlink (recommended)
ln -sfn ~/agent-skills ~/.agent/skills
```

Or use the helper script (auto-creates symlink):

```bash
~/agent-skills/scripts/ensure_agent_skills_mount.sh
```

### Step 3: Verify Setup

```bash
~/.agent/skills/mcp-doctor/check.sh
```

Expected output:
```
✅ ~/.agent/skills -> ~/agent-skills (symlink: ...)
✅ mcp-doctor: healthy
```

## Shared Profiles (bd-3871.5)

**Shared profiles** are skill-specific configuration files that define how a skill behaves across different environments.

### Profile Structure

Each skill can have an optional `profile.json`:

```json
{
  "name": "mcp-doctor",
  "version": "1.0.0",
  "environments": {
    "default": {
      "strict": false
    },
    "ci": {
      "strict": true
    }
  }
}
```

### Profile Discovery

Profiles are discovered in this order:

1. **Environment-specific** (e.g., `CI=true` → "ci" profile)
2. **User-specific** (`~/.agent/profiles/mcp-doctor.json`)
3. **Skill default** (`~/.agent/skills/mcp-doctor/profile.json`)
4. **Built-in defaults** (hardcoded in skill)

### Example: mcp-doctor Profiles

```bash
# Default profile (warn-only)
~/.agent/skills/mcp-doctor/check.sh

# Strict profile (fail on missing REQUIRED items)
MCP_DOCTOR_STRICT=1 ~/.agent/skills/mcp-doctor/check.sh

# CI profile (always strict)
CI=true ~/.agent/skills/mcp-doctor/check.sh
```

Profile selection:
- Local dev: Uses default profile (warn-only)
- CI/CD: Uses ci profile (strict, fails builds)
- Custom: User can override with `~/.agent/profiles/mcp-doctor.json`

## Shared Core (bd-3871.6)

**Shared core** refers to the common utilities and conventions that all skills can rely on.

### Core Conventions

1. **No secrets in output**
   - Skills MUST NOT print bearer tokens, API keys, or headers
   - Use environment variables for secrets
   - Log only paths, status, and non-sensitive metadata

2. **Warning-only locally, fail-loud in CI**
   - Local execution: Warn about issues, don't block
   - CI execution: Fail builds on missing REQUIRED items
   - Control via `<SKILL>_STRICT=1` or `CI=true`

3. **Idempotent operations**
   - Skills should be safe to run multiple times
   - Don't create duplicate state or fail on re-runs
   - Example: `ln -sfn` (force symlink creation)

4. **Clear exit codes**
   - `0`: Success
   - `1`: Warning (local) or failure (CI)
   - `2+`: Specific error codes (documented in SKILL.md)

### Core Utilities

Skills can rely on these shared utilities:

**1. Color output helpers** (copy/paste into scripts)

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }
```

**2. Git helpers** (common patterns)

```bash
# Get repo root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Check if repo is dirty
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Repository has uncommitted changes"
fi

# Get current branch
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo 'detached')"
```

**3. Safe file operations**

```bash
# Create symlink (idempotent)
ln -sfn ~/agent-skills ~/.agent/skills

# Backup before overwrite
BACKUP="$FILE.backup.$(date +%Y%m%d-%H%M%S)"
mv "$FILE" "$BACKUP"
```

### Core Documentation

All skills MUST have:

1. **SKILL.md** - Comprehensive documentation including:
   - Description and purpose
   - When to use (and when NOT to use)
   - Usage examples (copy/paste friendly)
   - Exit codes and error handling
   - Integration with other skills
   - Troubleshooting section

2. **Version history** - Track changes in SKILL.md:
   ```markdown
   ## Version History
   - **v1.0.0** (2025-12-13): Initial implementation
   - **v1.1.0** (2025-12-14): Added CI support
   ```

3. **Examples** - Practical, runnable examples:
   ```bash
   # Example 1: Basic usage
   ~/.agent/skills/skill-name/script.sh

   # Example 2: Custom options
   ~/.agent/skills/skill-name/script.sh --option value
   ```

## Integration with DX Bootstrap

The skills plane is part of the standard DX bootstrap sequence:

```bash
# 1. Git sync
cd ~/llm-common && git pull origin master

# 2. DX doctor check (includes mcp-doctor)
~/.agent/skills/dx-doctor/check.sh

# 3. Agent Mail (if configured)
# Register identity and check inbox

# 4. Beads sync (via primary repo)
# Sync state from prime-radiant-ai or affordabot
```

The mcp-doctor (part of dx-doctor) verifies:
- ✅ ~/.agent/skills mount is correct (REQUIRED)
- ⚠️  Optional MCPs (Slack, Supermemory, etc.)
- ⚠️  Optional CLIs (railway, gh)

See [DX_BOOTSTRAP_CONTRACT.md](./DX_BOOTSTRAP_CONTRACT.md) for full details.

## Maintenance

### Updating Skills

```bash
# Pull latest skills from GitHub
cd ~/agent-skills
git pull origin main

# Verify mount point is still correct
~/.agent/skills/mcp-doctor/check.sh
```

### Adding New Skills

1. Create skill directory: `~/agent-skills/new-skill/`
2. Add SKILL.md documentation
3. Add implementation scripts (optional)
4. Test locally
5. Open PR to `stars-end/agent-skills`
6. After merge, pull updates: `cd ~/agent-skills && git pull`

### Removing Old Skills

```bash
# Remove skill directory
cd ~/agent-skills
git rm -r old-skill/
git commit -m "chore: Remove deprecated old-skill"

# Or if not yet committed:
rm -rf old-skill/
```

## Troubleshooting

### "~/.agent/skills does not exist"

The canonical mount point is missing. Create it:

```bash
~/agent-skills/scripts/ensure_agent_skills_mount.sh
```

Or manually:

```bash
mkdir -p ~/.agent
ln -sfn ~/agent-skills ~/.agent/skills
```

### "~/.agent/skills points to wrong target"

The mount point exists but points to the wrong location. Fix it:

```bash
# Remove incorrect symlink/directory
rm ~/.agent/skills

# Create correct symlink
ln -sfn ~/agent-skills ~/.agent/skills

# Verify
ls -la ~/.agent/skills
```

## Railway Skills (Official Integration)

Railway has created an official set of agent skills for interacting with their platform, now integrated as part of the core agent-skills repository.

### Available Railway Skills

| Skill | Description |
|-------|-------------|
| **status** | Check Railway project status |
| **projects** | List, switch, and configure projects |
| **new** | Create projects, services, databases |
| **service** | Manage existing services |
| **deploy** | Deploy local code |
| **domain** | Manage service domains |
| **environment** | Manage config (vars, commands, replicas) |
| **deployment** | Manage deployments (list, logs, redeploy, remove) |
| **database** | Add Railway databases |
| **templates** | Deploy from marketplace |
| **metrics** | Query resource usage |
| **railway-docs** | Fetch up-to-date Railway documentation |

### Installation

Railway skills are included in `~/agent-skills/railway/`. No additional installation needed if you have agent-skills mounted at `~/.agent/skills`.

### Usage

Each skill has a `SKILL.md` file with detailed instructions. Example for `railway/status`:

```bash
# Check Railway project status
~/.agent/skills/railway/status/SKILL.md
```

### External Source

Railway skills are maintained by Railway at:
- **Repository**: https://github.com/railwayapp/railway-skills
- **Website**: https://railway.com/skills.sh

The skills are synchronized periodically into agent-skills to ensure core integration.

## Related Documentation

- [railway/status](./railway/status/SKILL.md) - Railway status checking
- [railway/deploy](./railway/deploy/SKILL.md) - Railway deployment
- [mcp-doctor](./mcp-doctor/SKILL.md) - MCP server health checks
- [dirty-repo-bootstrap](./dirty-repo-bootstrap/SKILL.md) - WIP repo recovery (bd-3871.15)
- [DX_BOOTSTRAP_CONTRACT.md](./DX_BOOTSTRAP_CONTRACT.md) - Session start requirements
- [CONTRIBUTING.md](./CONTRIBUTING.md) - How to contribute new skills

## Version History

- **v1.1.0** (2025-01-21): Railway official skills integration
  - Added Railway skills as core skill set (12 skills from railwayapp/railway-skills)
  - Skills: status, projects, new, service, deploy, domain, environment, deployment, database, templates, metrics, railway-docs
  - External source: https://github.com/railwayapp/railway-skills

- **v1.0.0** (2025-12-13): Initial implementation
  - bd-3871.5: Shared profiles architecture
  - bd-3871.6: Shared core invariants
  - Canonical mount point: `~/.agent/skills -> ~/agent-skills`
  - Discovery precedence: MCP → filesystem → repo-local
  - Integration with DX bootstrap
