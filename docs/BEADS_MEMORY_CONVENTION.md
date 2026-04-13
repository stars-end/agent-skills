# Beads Memory Convention

Use Beads as the durable memory layer across VMs, repos, and agents. The
memory system is centralized through `bdx` on the canonical runtime and does
not require a separate memory daemon.

## Decision

`ALL_IN_NOW`: use Beads primitives as the canonical memory surface.

`DEFER_TO_P2_PLUS`: add a dedicated memory wrapper only after repeated operator
friction proves the convention is not enough.

Agent-facing workflow: use `core/beads-memory/SKILL.md` when storing or
retrieving reusable cross-agent knowledge.

## Three Memory Tiers

1) Short global facts (Beads KV, prime-injected upstream):

- `bdx remember`
- `bdx memories`
- `bdx recall`
- `bdx forget`

Use stable keys and concise facts that should be visible across sessions.

```bash
bdx remember \
  "z.ai web-reader behavior may use chat-style endpoints; verify endpoint shape before integration" \
  --key vendor-zai-web-reader-chat-endpoint-gotcha
```

2) Structured durable memory (closed Beads issues labeled `memory`):

- Use normal Beads issues for provenance, metadata, comments, staleness, and
  cross-repo lessons.
- These records may be tied to a task or standalone/global.
- Close memory records after capture to keep active queues clean.

```bash
bdx create \
  "Memory: z.ai web-reader endpoint behavior" \
  --type decision \
  --priority 4 \
  --labels memory,vendor,zai,api \
  --description "z.ai integrations may expose web-reader behavior via chat endpoints. Verify current docs and client behavior before assuming a separate reader endpoint." \
  --metadata '{"mem.kind":"gotcha","mem.scope":"vendor","mem.repo":"global","mem.maturity":"validated","mem.confidence":"medium","mem.source_issue":"none","mem.query_hint":"zai web reader endpoint chat"}'
```

3) Task-local history:

- `bdx comments add <issue-id> ...`
- Comments are for task-local chronology only.
- Do not treat comments as global memory unless promoted into tier 1 or tier 2.

## Required Structured Metadata

Required fields on `memory` issues:

- `mem.scope`: `global|repo|tool|vendor|workflow`
- `mem.repo`: repo name or `global`
- `mem.source_issue`: concrete issue id or `none`
- `mem.kind`: `decision|runbook|learning|gotcha|handoff|best_practice`
- `mem.maturity`: `draft|validated|core`
- `mem.confidence`: `low|medium|high`

Optional fields:

- `mem.paths`
- `mem.stale_if_paths`
- `mem.source_commit`
- `mem.query_hint`
- `mem.symbols`

## Standalone / Global Memory Records

Standalone memory is explicitly allowed. Use it when a learning is not tied to
a single task but should persist fleet-wide.

Rules:

- set `mem.scope` correctly (often `global`, `tool`, `vendor`, or `workflow`)
- set `mem.repo=global` for cross-repo memory
- set `mem.source_issue=none` when there is no originating issue
- close the memory issue after capture

## Cross-VM / Cross-Repo Usage

- `bdx` is the canonical coordination and memory surface across all VMs/repos.
- Search memory before:
  - cross-VM work
  - cross-repo work
  - vendor/API decisions
  - infra/auth/workflow fixes
  - repeated-friction incidents
- Do not require memory search for trivial, routine task edits.

## Retrieval Workflow

Use targeted retrieval before acting:

```bash
bdx memories <keyword> --json
bdx search <keyword> --label memory --status all --json
bdx show <memory-id> --json
bdx comments <memory-id> --json
```

## llm-tldr Synergy (Verification)

Memory is a lead, not proof.

After retrieval:

- verify memory claims against current source with `llm-tldr`
- validate any `mem.stale_if_paths` and `mem.paths` before applying memory
- update memory maturity/confidence if source changed materially

## serena Synergy (Execution)

Memory can store `mem.paths` and `mem.symbols` to accelerate editing, but
symbol operations should still run through `serena` after memory + `llm-tldr`
validation.

Flow:

1. retrieve memory
2. verify with `llm-tldr`
3. execute precise symbol edits with `serena`

## Staleness Handling

When source paths or commits changed, downgrade confidence and revalidate:

```bash
bdx update <memory-id> \
  --set-metadata mem.maturity=draft \
  --set-metadata mem.confidence=medium \
  --append-notes "Revalidation required: referenced source paths changed."
```
