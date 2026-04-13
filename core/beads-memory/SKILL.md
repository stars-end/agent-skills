---
name: beads-memory
description: |
  Durable Beads memory workflow for cross-VM, cross-repo, and cross-agent knowledge.
  MUST BE USED when storing or retrieving reusable memory, gotchas, best practices,
  vendor/tool quirks, workflow learnings, or when the user says remember, recall,
  memory, "we learned", "document this for agents", or "make sure agents know".
tags: [workflow, beads, memory, cross-vm, cross-repo, agents]
allowed-tools:
  - Read
  - Bash(bdx:*)
---

# Beads Memory

Use existing Beads primitives as the durable memory layer before adding a new
memory service or wrapper.

## Contract

- `bdx` is the canonical cross-VM/cross-repo memory surface.
- Short global facts use Beads KV via `bdx remember`, `bdx memories`,
  `bdx recall`, and `bdx forget`.
- Structured durable memory uses ordinary Beads issues labeled `memory`.
- Task chronology stays in `bdx comments add`; promote it to memory only when it
  should survive outside the originating task.
- Memory is a lead, not proof. Verify source-grounded claims before acting.

## When To Retrieve Memory

Run targeted memory lookup before non-trivial work involving:

- cross-VM or cross-repo coordination
- vendor/API behavior
- infra/auth/workflow fixes
- repeated DX friction
- decisions that should affect future agents

Skip memory lookup for trivial routine edits.

```bash
bdx memories <keyword> --json
bdx search <keyword> --label memory --status all --json
bdx show <memory-id> --json
bdx comments <memory-id> --json
```

## When To Store Short Facts

Use `bdx remember` for concise facts that should be visible in Beads prime
context and are not worth a full issue.

```bash
bdx remember \
  "z.ai web-reader behavior may use chat-style endpoints; verify endpoint shape before integration" \
  --key vendor-zai-web-reader-chat-endpoint-gotcha
```

Use stable keys. Prefer `vendor-`, `tool-`, `workflow-`, `repo-`, or `infra-`
prefixes so future agents can search predictably.

## When To Store Structured Memory

Create a closed Beads issue labeled `memory` when the learning needs provenance,
comments, metadata, staleness tracking, or cross-repo visibility.

```bash
bdx create \
  "Memory: z.ai web-reader endpoint behavior" \
  --type decision \
  --priority 4 \
  --labels memory,vendor,zai,api \
  --description "z.ai integrations may expose web-reader behavior via chat endpoints. Verify current docs and client behavior before assuming a separate reader endpoint." \
  --metadata '{"mem.kind":"gotcha","mem.scope":"vendor","mem.repo":"global","mem.maturity":"validated","mem.confidence":"medium","mem.source_issue":"none","mem.query_hint":"zai web reader endpoint chat"}'
```

Required metadata for structured memory:

- `mem.scope`: `global|repo|tool|vendor|workflow`
- `mem.repo`: repo name or `global`
- `mem.source_issue`: concrete Beads id or `none`
- `mem.kind`: `decision|runbook|learning|gotcha|handoff|best_practice`
- `mem.maturity`: `draft|validated|core`
- `mem.confidence`: `low|medium|high`

Useful optional metadata:

- `mem.paths`
- `mem.stale_if_paths`
- `mem.source_commit`
- `mem.query_hint`
- `mem.symbols`

Close memory issues after capture so memory records do not pollute active work
queues.

## Tool Synergy

- Use Beads memory to find prior knowledge.
- Use `llm-tldr` to verify current source, impact, call paths, and stale paths.
- Use `serena` only for explicit symbol-aware edits after retrieval and
  verification.

Do not use Serena memory as the durable shared memory layer.

## Reference

Full convention: `~/agent-skills/docs/BEADS_MEMORY_CONVENTION.md`
