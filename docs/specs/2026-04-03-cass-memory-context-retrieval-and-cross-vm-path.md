# bd-dk79 — CASS Memory Context Retrieval and Cross-VM Path

## Summary

Ground the `cass-memory` pilot in the actual upstream `~/cass_memory_system`
contracts:

1. `cm context "<task>" --json` is the primary retrieval surface
2. `cm context` returns its payload under `.data.relevantBullets`
3. `cm similar` is the broader fallback for loose phrase matching
4. cross-VM history already exists upstream via `remoteCass`
5. cross-VM procedural rule sharing does **not** happen automatically; promoted
   playbook bullets still need an explicit distribution path

This means the immediate pilot should:

1. use task-shaped `cm context` queries first
2. inspect the correct JSON path
3. keep `cm similar` for low-threshold discovery and QA
4. treat cross-VM sharing as a two-layer design:
   - remote history via `remoteCass`
   - promoted playbook rule distribution via explicit export/import

## Ground Truth From Upstream Docs and Code

### Retrieval contract

Upstream README positions:

```bash
cm context "<your task>" --json
```

as the primary agent read path.

Relevant references:

- `~/cass_memory_system/README.md`
- `~/cass_memory_system/src/commands/context.ts`
- `~/cass_memory_system/src/utils.ts`

### Why retrieval looked weaker than it was

During pilot probing, two issues made `cm context` look worse than it is:

1. some checks inspected `.relevantBullets` instead of `.data.relevantBullets`
2. some probes were loose noun-phrase searches rather than task-shaped queries

The current CLI returns:

```json
{
  "success": true,
  "command": "context",
  "data": {
    "task": "...",
    "relevantBullets": [...]
  }
}
```

### Current scoring behavior

In `src/commands/context.ts`, playbook bullets are filtered by
`config.minRelevanceScore`.

The relevance score comes from:

- keyword overlap via `scoreBulletRelevance(...)`
- optional semantic similarity if `semanticSearchEnabled` is true

Current pilot host config still has:

```json
"semanticSearchEnabled": false
```

So the live pilot is effectively keyword-first today.

### What this means for the pilot

Task-shaped operator queries already work if they contain the same operational
language as the promoted bullet.

Examples that retrieved correctly during validation:

- `cm context "prefer z.ai coding endpoints first" --json`
- `cm context "op cli dev secrets service account auth checks" --json`
- `cm context "use 1password service account for dev auth instead of ambient env" --json`

So the current blocker is **not** "context is unusable".

The real contract is:

1. write promoted bullets in task-friendly operator language
2. query `cm context` with task-like wording
3. inspect `.data.relevantBullets`
4. use `cm similar` for looser recall, QA, and wording discovery

## Cross-VM Sharing Design

### What upstream already gives us

Upstream `remoteCass` is an SSH-based remote history path.

Relevant code/docs:

- `~/cass_memory_system/src/cass.ts`
- `~/cass_memory_system/src/types.ts`
- `~/cass_memory_system/README.md`

When enabled, `cm context` can include remote history snippets with:

- `historySnippets[].origin.kind = "remote"`
- `historySnippets[].origin.host = <host>`

This helps with cross-VM **episodic** memory.

### What upstream does not give us automatically

`remoteCass` does not automatically merge or replicate promoted playbook bullets
across machines.

So if the founder goal is:

> stop repeating stable operator heuristics across agents and VMs

then cross-VM sharing needs two explicit layers:

1. **history layer**
   - use `remoteCass` for cross-machine cass history lookup
2. **procedural rule layer**
   - distribute promoted playbook bullets explicitly

### Recommended pilot path

#### Phase 1: Local-first retrieval

Keep the current pilot local-first:

- candidate docs stay in `agent-skills`
- promoted bullets go into local `cm playbook`
- `cm context` is the default read path

#### Phase 2: Cross-VM history

Enable `remoteCass` only on hosts where:

1. SSH access is already healthy
2. `cass` is installed and indexed remotely
3. privacy posture is acceptable

Suggested config shape:

```json
"remoteCass": {
  "enabled": true,
  "hosts": [
    { "host": "macmini", "label": "macmini" },
    { "host": "epyc12", "label": "epyc12" }
  ]
}
```

This is useful for:

- prior-session incident evidence
- prior debugging traces
- historical context that supports a rule

#### Phase 3: Cross-VM procedural rule sync

Do **not** auto-sync raw candidates.

Only sync promoted bullets, using explicit export/import.

Upstream already supports:

```bash
cm playbook export > playbook-backup.yaml
cm playbook import shared-playbook.yaml
```

Recommended pilot contract:

1. promote locally first
2. export a sanitized promoted-rules snapshot
3. import that snapshot on other pilot hosts
4. keep repo docs as the audit trail

This gives us deliberate cross-VM rule sharing without turning the pilot into
ambient replication of every local experiment.

## Recommended Operator Guidance

### Retrieval

Use:

```bash
cm context "<task-shaped operator query>" --json
```

Inspect:

```bash
jq '.data.relevantBullets'
```

Use `cm similar` when:

1. you are probing wording
2. you want a loose neighborhood search
3. you are QA-ing whether a bullet is discoverable

### Cross-VM enablement

Use `remoteCass` when you want:

1. remote historical evidence
2. cross-machine incident recall

Do **not** treat `remoteCass` as the promoted-rule sync mechanism.

### Promoted-rule sync

For the pilot, sync only promoted rules and only explicitly.

That keeps the shared memory clean enough to support founder-level operator
preferences such as:

- use `op` CLI for dev secrets
- prefer Z.AI coding endpoints first
- verify deploy identity before trusting remote failures

## Validation Notes

Validated locally against current pilot bullets:

1. task-shaped `cm context` queries retrieved the intended operator bullets
2. the correct JSON path is `.data.relevantBullets`
3. `remoteCass` is documented and implemented upstream as SSH-based history, not
   automatic playbook replication

## Decision

For the current pilot:

1. keep `cm context` as the default read path
2. tighten our docs so agents use task-shaped queries and the correct JSON path
3. keep `cm similar` as the broader fallback
4. design cross-VM sharing as:
   - `remoteCass` for history
   - explicit playbook export/import for promoted rules

## Beads Mapping

- Epic: `bd-umkg`
- Task: `bd-dk79`
