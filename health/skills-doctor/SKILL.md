---
name: skills-doctor
description: Validate that the current VM has the right `agent-skills` installed for the repo you’re working in.
---

# skills-doctor

## Description

Validate that the current VM has the right `agent-skills` installed for the repo you’re working in.

This is a **soft** doctor: it reports issues and suggested fixes, but should not block work.

**Use when**:
- Agents are missing required skills (dx-doctor, lockfile-doctor, railway-doctor, etc.)
- You suspect `~/.agent/skills` is stale on a VM
- You want a quick “is my skills stack correct for this repo?” check

## How it works

The doctor performs two classes of checks:

### 1. Skills-Plane Health (local diagnosis)

Verifies the shared skills plane at `~/.agent/skills` is properly installed:

- `~/.agent/skills` exists (as symlink or directory)
- Symlink target points at expected canonical location (e.g., `~/agent-skills`)
- `AGENTS.md` exists in the skills plane
- Baseline artifact exists (`dist/universal-baseline.md`)
- Required skill directories exist for the repo profile
- Reports installed SHA for version tracking

### 2. Repo-Specific Skill Checks

- Picks a repo profile from `skill-profiles/` based on your repo’s `origin` remote URL.
- Checks that each required skill directory exists under `~/.agent/skills` (or `AGENT_SKILLS_DIR`).
- Prints a small actionable summary.

## Architecture

The skills plane follows a **one shared plane per VM** model:

```
~/.agent/skills -> ~/agent-skills (symlink)
```

Multiple IDE/client surfaces (claude-code, opencode, gemini-cli, etc.) consume this shared plane
through their own bootstrap/config rails (e.g., `~/.claude/CLAUDE.md` -> `~/.agent/skills/AGENTS.md`).

This doctor checks the shared plane locally. For fleet-wide skills alignment, see
`dx-fleet check --mode weekly` which includes:
- `skills_plane_alignment` - Fleet-wide skills plane health
- `ide_bootstrap_alignment` - IDE bootstrap/config rail alignment

## Usage

```bash
# From inside a repo (prime-radiant-ai, affordabot, llm-common)
~/.agent/skills/skills-doctor/check.sh
```

Optional overrides:

```bash
export AGENT_SKILLS_DIR=”$HOME/.agent/skills”
export SKILLS_DOCTOR_PROFILE=”prime-radiant-ai”   # or affordabot, llm-common
~/.agent/skills/skills-doctor/check.sh
```

For JSON output (useful in fleet checks):

```bash
~/.agent/skills/health/skills-doctor/check.sh --json
```

## Exit Codes

- `0`: All checks pass
- `1`: Missing skills or skills-plane issues detected
- `2`: Warnings only (recommended skills missing)

