---
name: dx-research
description: |
  Source-backed deep research wrapper over dx-runner for agent use.
  Use when the goal is evidence-based research and decision memo output,
  not implementation dispatch or code-review quorum.
tags: [workflow, research, evidence, decision-memo, dx-runner, gemini, cc-glm]
allowed-tools:
  - Bash
---

# dx-research

`dx-research` is a task-specific shim over `dx-runner` for research outcomes.
It is the default agent surface for source-backed web/deep research and decision
memos.

Routing boundaries:
- `dx-review`: independent code/design/security review quorum
- `dx-research`: source-backed research + decision memo artifacts
- `dx-runner`: provider substrate and manual escape hatch

Provider detail is intentionally hidden for normal agent use. Treat Gemini
(`gemini -y`) as an internal implementation detail behind the
`gemini-research` profile, not an AGENTS-level instruction.

## Required Command Shape

```bash
dx-research run \
  --beads bd-xxx \
  --worktree /tmp/agents/bd-xxx/repo \
  --topic "compare option A vs B for X" \
  --depth deep \
  --wait
```

`--worktree` defaults to the current directory. Pass it explicitly when the
research needs repo-local evidence or when running from a control-plane shell.

Then read the merged artifact first:

```bash
dx-research summarize --beads bd-xxx
```

## Artifacts

Per run, artifacts live under:

```text
/tmp/dx-research/<beads-id>/
```

Required files:
- `research.prompt`
- `summary.json`
- `summary.md`
- `sources.json`
- `claims.json`

Low cognitive load rule:
- Agents read `summary.md` first.
- Raw logs/reports are for debugging only.

## summary.md Contract

`summary.md` must contain these sections:
- `Answer`
- `Evidence`
- `Contradictions`
- `Confidence`
- `Decision Impact`
- `Open Questions`
- `Next Action`

## Source-Grounding Contract

Major claims must include one of:
- source ids linked to `sources.json`, or
- explicit `inference` labels when direct grounding is unavailable.

Research output must distinguish:
- web facts (external sources), and
- repo/local facts (workspace files, local docs, logs).

## Scope Controls

Use `--no-web` when external browsing is not allowed for the task.

Use `--local-only` when the task should rely only on repo/local evidence and
must not use external sources.

Both modes still require explicit claim grounding in `sources.json` and
`claims.json` (or explicit inference labels).
