---
name: skill-factory
description: Meta-skill for creating new skills and ensuring AGENTS.md is regenerated. Use when adding new skills or recompiling the agent index.
tags: [meta, skill-creation, automation]
allowed-tools:
  - Bash
  - Write
  - Read
---

# Skill Factory

Automates the creation and registration of new agent skills.

## Purpose
To standardize skill creation and ensure `AGENTS.md` is always up-to-date with new skills.

## When to Use
- Adding a new skill from a URL or raw content.
- Re-compiling `AGENTS.md` manually.

## Workflow

### 1. Create Skill Directory
Creates the directory structure for the new skill.
\`\`\`bash
mkdir -p ~/agent-skills/<category>/<skill-name>
\`\`\`

### 2. Write SKILL.md
Writes the `SKILL.md` file with provided content.

### 3. Regenerate Index
Runs the regeneration script to update `AGENTS.md`.
\`\`\`bash
cd ~/agent-skills
make regenerate-agents-md
\`\`\`

### 4. Verify
Checks if the new skill appears in `AGENTS.md`.

## Integration
- **Makefile**: Uses `make regenerate-agents-md`.
- **Git**: Should be run in a worktree to avoid canonical violations.

## Examples

**Add a new skill:**
\`\`\`bash
# (Conceptually)
skill-factory add --name "my-skill" --category "extended" --content "..."
\`\`\`

**Regenerate index:**
\`\`\`bash
# (Conceptually)
skill-factory recompile
\`\`\`
