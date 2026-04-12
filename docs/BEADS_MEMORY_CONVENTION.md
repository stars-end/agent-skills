# Beads Memory Convention

Use Beads as the durable memory layer before adding a separate memory service.
The goal is cross-session, cross-VM recall with no new daemon, database, or
manual founder monitoring.

## Decision

`ALL_IN_NOW`: use existing Beads primitives for durable agent memory.

`DEFER_TO_P2_PLUS`: add a dedicated `bd-mem` wrapper only if agents repeatedly
misuse the command shape or retrieval convention.

## Routing

- Current code truth: use `llm-tldr`, then inspect source as needed.
- Durable task state: use normal Beads issues, dependencies, and comments.
- Durable memory: use `bdx remember` for short facts and Beads issues labeled
  `memory` for structured records.
- Never trust memory over current code. Treat memory as a lead, then verify
  source-grounded claims with `llm-tldr` or direct file inspection.

## What To Store

Store memory only when it reduces future cognitive load:

- Architectural decisions that should survive a thread or VM change.
- Repeated gotchas, failed approaches, and recovery procedures.
- Cross-repo conventions that are easy to forget.
- Source-grounded facts that were expensive to discover.
- Handoff notes that explain why work is shaped a certain way.

Do not store ordinary task progress, speculative guesses, or facts that are
trivial to rediscover from current code.

## Short Facts

Use `bdx remember` for small, global facts:

```bash
cd ~
bdx remember \
  "agent-skills changes must happen in /tmp/agents/<beads-id>/agent-skills, not ~/agent-skills" \
  --key agent-skills-worktree-only
```

Search and recall:

```bash
cd ~
bdx memories worktree
bdx recall agent-skills-worktree-only
```

## Structured Memory Records

Use Beads issues for memory that needs provenance, metadata, comments, links, or
staleness checks.

```bash
cd ~
bdx create \
  "Memory: agent-skills worktree-only editing policy" \
  --type decision \
  --priority 3 \
  --labels memory,agent-skills,workflow \
  --description "Agents must edit agent-skills through dx-worktree workspaces. Canonical ~/agent-skills is read-mostly." \
  --notes "Verify current repo policy in AGENTS.md before mutating files." \
  --metadata '{"mem.kind":"decision","mem.repo":"agent-skills","mem.maturity":"validated","mem.confidence":"high","mem.source_issue":"bd-q0f7s","mem.source_commit":"","mem.paths":["AGENTS.md","docs/BEADS_MEMORY_CONVENTION.md"]}'
```

Add provenance or follow-up detail as comments:

```bash
bdx comments add <memory-id> \
  "Source: discovered while documenting Beads memory convention. Verify with llm-tldr before applying to changed repo policy."
```

## Metadata Keys

Use these keys for structured memory records:

- `mem.kind`: `decision`, `runbook`, `learning`, `gotcha`, or `handoff`.
- `mem.repo`: repo name such as `agent-skills`, `prime-radiant-ai`, or `llm-common`.
- `mem.maturity`: `draft`, `validated`, or `core`.
- `mem.confidence`: `low`, `medium`, or `high`.
- `mem.source_issue`: Beads issue that produced the memory.
- `mem.source_commit`: commit SHA when known.
- `mem.paths`: source paths that ground the memory.
- `mem.stale_if_paths`: paths whose changes should trigger revalidation.

## Retrieval

Before cross-repo, repeated, or confusing work, search memory first:

```bash
cd ~
bdx memories <keyword>
bdx search <keyword> --label memory --status all
bdx search memory --label memory --metadata-field mem.repo=agent-skills --status all
bdx search gotcha --label memory --metadata-field mem.kind=gotcha --status all
```

Then inspect the specific record:

```bash
bdx show <memory-id>
bdx comments <memory-id>
```

## Staleness

If a memory cites paths or commits, treat it as stale when those files changed
materially after the recorded source commit. Update the memory by comment or
metadata rather than silently relying on it.

```bash
bdx update <memory-id> \
  --set-metadata mem.maturity=draft \
  --set-metadata mem.confidence=medium \
  --append-notes "Marked draft because cited source paths changed; revalidate before reuse."
```

## When A Wrapper Becomes Worth It

Add a `bd-mem` helper only after observing repeated failures in one of these
areas:

- Agents forget required metadata.
- Agents store memory in comments when it needs a searchable issue.
- Agents cannot reliably retrieve records by repo/kind/maturity.
- Stale-source checks become frequent enough to automate.

Until then, the convention is the surface.
