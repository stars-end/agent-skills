# DX Fleet Specification v7.7

**Date**: 2026-02-04  
**Status**: Active  
**Replaces**: v7.6

## Summary

v7.7 introduces repo-plane baseline inheritance and an optional tool-global "tiny rail" for cross-IDE constraints.

## 1. Repo-Plane Inheritance (Mandatory)

### 1.1 Product Repo Structure

Each product repo (prime-radiant-ai, affordabot, llm-common) must implement:

```
repo-root/
├── fragments/
│   ├── universal-baseline.md          # Downloaded from agent-skills
│   └── repo-addendum.md               # Optional repo-specific rules
├── scripts/agents-md-compile.zsh      # Deterministic compiler
├── AGENTS.md                          # Generated output
└── .github/workflows/
    ├── baseline-sync.yml              # Daily baseline sync
    └── verify-agents-md.yml           # PR verification
```

### 1.2 Baseline Sync Workflow

- **Trigger**: Daily cron + `workflow_dispatch`
- **Action**: Downloads `dist/universal-baseline.md` from agent-skills
- **Safety**: Creates `fragments/` directory if missing (`mkdir -p fragments`)
- **Auto-PR**: Opens/updates rolling draft PR on changes
- **Branch**: `bot/agent-baseline-sync`

### 1.3 AGENTS.md Compiler

`scripts/agents-md-compile.zsh` must:

1. Concatenate `fragments/universal-baseline.md` (required)
2. Append `fragments/repo-addendum.md` (optional)
3. Output to `AGENTS.md`
4. Use deterministic ordering

### 1.4 Verification Workflow

`verify-agents-md.yml` triggers on PR when:
- `fragments/**` changed
- `AGENTS.md` changed
- Compile script changed

**Behavior**: Regenerates AGENTS.md and fails CI if diff exists.

## 2. Tool-Global "Tiny Rail" (Optional)

### 2.1 Purpose

A minimal constraint file for IDE global configuration (symlinked, not embedded).

### 2.2 Source Location

```
~/agent-skills/fragments/dx-global-constraints.md     # Source
~/agent-skills/dist/dx-global-constraints.md          # Published
```

### 2.3 Content Constraints

- Maximum ~20 lines
- Versionless
- Universal hard constraints only

Current content:
```markdown
## DX Global Constraints (Always-On)

1) **NO WRITES** in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) **Worktree first**: `dx-worktree create <id> <repo>`
3) **Before "done"**: run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) For full rules, read repo `AGENTS.md` / `GEMINI.md`.
```

### 2.4 Per-VM Setup (Manual)

```bash
# Symlink to tool global configs
mkdir -p ~/.codex ~/.gemini ~/.config/opencode
ln -sf ~/agent-skills/dist/dx-global-constraints.md ~/.codex/AGENTS.md
ln -sf ~/agent-skills/dist/dx-global-constraints.md ~/.gemini/GEMINI.md
ln -sf ~/agent-skills/dist/dx-global-constraints.md ~/.config/opencode/AGENTS.md
```

**Important**: Do NOT embed full AGENTS.md in tool globals. Use the tiny rail symlink pattern.

## 3. Migration from v7.6

1. Merge agent-skills v7.7 first
2. Roll out baseline inheritance to each product repo
3. Optionally configure per-VM tool symlinks

## 4. Acceptance Criteria

- [ ] `dist/dx-global-constraints.md` publishes correctly
- [ ] Each product repo has working baseline-sync.yml
- [ ] Each product repo has verify-agents-md.yml that fails on stale AGENTS.md
- [ ] `dx-verify-clean.sh` passes on all canonical clones
