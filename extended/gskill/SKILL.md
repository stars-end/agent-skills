---
name: gskill
description: Auto-learn repository-specific skills for coding agents using SWE-smith + GEPA. Generates synthetic tasks and evolves skills through reflective optimization. Use when you want to improve agent performance on a specific repository.
tags: [skill-learning, gepa, swe-smith, optimization, auto-ml]
activation:
  - "learn skills"
  - "evolve skills"
  - "gskill"
  - "auto-learn"
  - "skill optimization"
---

# gskill - Auto-Learn Skills for Coding Agents

Automatically learn repository-specific skills by generating synthetic tasks and evolving skills through reflective optimization.

## When to Use

- Agent is making similar mistakes on a repo
- Want to improve agent pass rate on specific codebase
- Setting up a new repo for agent work
- After significant codebase changes

## Prerequisites

- SWE-smith installed at `~/SWE-smith`
- GEPA installed at `~/gepa`
- opencode available in PATH
- Target repo has tests

## Commands

### Generate Tasks

```bash
gskill generate-tasks --repo ~/prime-radiant-ai --max-tasks 100
```

Creates `~/prime-radiant-ai/.gskill/tasks.jsonl` with synthetic bug-fix tasks.

### Evolve Skills

```bash
gskill evolve --repo ~/prime-radiant-ai
```

Runs GEPA optimization loop. Outputs learned skill to `.gskill/learned/SKILL.md`.

### Evaluate Skill

```bash
gskill evaluate --repo ~/prime-radiant-ai --skill .gskill/learned/SKILL.md
```

Tests a skill against tasks to measure pass rate.

## Workflow

1. **Generate tasks** for your repo (one-time or after major changes)
2. **Evolve skills** using GEPA (takes 1-4 hours depending on max_metric_calls)
3. **Review** learned skill in `.gskill/learned/SKILL.md`
4. **Install** skill to `.claude/skills/learned/SKILL.md` in target repo
5. **Measure** improvement with `gskill evaluate`

## Output

Learned skills are stored in:

```
{repo}/.gskill/
├── tasks.jsonl           # Generated tasks
├── evolution_log.jsonl   # GEPA iteration log
└── learned/
    └── SKILL.md          # Learned skill
```

## Example Learned Skill

```markdown
3) Always check for NULL before aggregation
- Pattern: `COALESCE(column, 0)` or `column IS NOT NULL`
- Failure: NULL propagates, crashes downstream
- Test: `test_null_handling.py`

7) Use idempotent upserts for sync operations
- Pattern: `ON CONFLICT (id) DO UPDATE`
- Failure: Duplicate rows on retry
- Test: `test_sync_idempotency.py`
```

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_metric_calls` | 100 | GEPA evaluation budget |
| `reflection_model` | glm-5 | LLM for skill reflection |
| `language` | python | Target language (python, typescript, javascript) |

## Related Skills

- `skill-creator` - For manual skill creation
- `context-*` - Repo-specific context skills

## References

- GEPA: https://github.com/gepa-ai/gepa
- SWE-smith: https://github.com/SWE-bench/SWE-smith
- gskill blog: https://gepa-ai.github.io/gepa/blog/2026/02/18/automatically-learning-skills-for-coding-agents/
