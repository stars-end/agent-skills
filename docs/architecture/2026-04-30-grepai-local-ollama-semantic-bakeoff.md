# grepai Local Ollama Semantic Bakeoff

**Date**: 2026-04-30
**BEADS_EPIC**: bd-9n1t2.30
**BEADS_SUBTASK**: bd-9n1t2.30.1
**Feature-Key**: bd-9n1t2.30.1
**Mode**: qa_pass
**Candidate**: grepai 0.35.0 with local Ollama `nomic-embed-text`
**Existing PR**: https://github.com/stars-end/agent-skills/pull/600

## Verdict

**Verdict: async/on-demand semantic enrichment only**

grepai should not replace or become the mandatory first-hop successor to
`llm-tldr semantic`. With a warm local index, it can return relevant semantic
results, but local query embedding costs seconds per query and the readiness
surface is not machine-safe enough for default agent routing.

The useful product shape is explicit enrichment: run grepai only when a managed
Ollama service, model, and completed per-worktree index are already known-good.
The default critical path should stay `rg` / direct reads, with `serena` for
known-symbol edits.

## Source Of Truth Read First

Read coordinator synthesis PR #603 head
`260210c62f54a22fa8fedaccde60ac285f049d0e`:

```bash
git fetch origin pull/603/head:refs/remotes/origin/pr-603
git show 260210c62f54a22fa8fedaccde60ac285f049d0e:docs/architecture/2026-04-30-final-llm-tldr-replacement-bakeoff-synthesis.md
```

Relevant coordinator finding: the prior grepai worker evidence was incomplete
because Ollama was absent. This rerun verifies the repaired local-Ollama lane.

Beads preflight comments were read:

```bash
bdx show bd-9n1t2.30.1 --json
bdx comments bd-9n1t2.30.1 --json
```

The Beads comment said the host should have grepai 0.35.0, Ollama 0.22.0, an
active `ollama-user.service`, and `nomic-embed-text:latest`.

## Infra Preflight

Ran in `/tmp/agents/bd-9n1t2.30.1/agent-skills`:

```bash
grepai version
ollama --version
systemctl --user is-active ollama-user.service
ollama list
```

Observed:

```text
grepai version 0.35.0
ollama version is 0.22.0
active
nomic-embed-text:latest    0a109f422b47    274 MB
```

Setup was already installed. No secrets were needed. No OpenRouter or cloud
embedding path was used.

## Exact Local Config

Command:

```bash
timeout 60 grepai init --provider ollama --model nomic-embed-text --backend gob --yes
```

Non-secret generated config:

```yaml
version: 1
embedder:
  provider: ollama
  model: nomic-embed-text
  endpoint: http://localhost:11434
  dimensions: 768
  parallelism: 0
store:
  backend: gob
chunking:
  size: 512
  overlap: 50
watch:
  debounce_ms: 500
search:
  boost:
    enabled: true
  hybrid:
    enabled: false
rpg:
  enabled: false
  llm_provider: ollama
  llm_endpoint: http://localhost:11434/v1
ignore:
  - .git
  - .grepai
  - node_modules
  - vendor
  - bin
  - dist
  - __pycache__
  - .venv
  - venv
```

`grepai init` created `.grepai/config.yaml` and appended `.grepai/` to the repo
`.gitignore`. That `.gitignore` change is intentional for worktree containment.

## Commands Used

All benchmark commands were bounded:

```bash
dx-worktree create bd-9n1t2.30.1 agent-skills
dx-worktree create bd-9n1t2.30.1 affordabot
timeout 30 grepai watch --stop
rm -rf .grepai
timeout 60 grepai init --provider ollama --model nomic-embed-text --backend gob --yes
timeout 60 grepai watch --background
timeout 20 grepai status --no-ui
timeout 30 grepai search --json --limit 3 "<query>"
timeout 30 grepai watch --stop
```

A foreground smoke attempt was also bounded. `/usr/bin/time` is not installed on
this host, so timing used Python `time.perf_counter()` wrappers.

## Results Summary

| Measurement | agent-skills | affordabot | Notes |
|---|---:|---:|---|
| install/preflight | already installed | already installed | grepai 0.35.0, Ollama 0.22.0 |
| init | 0.03s when already initialized; subsecond from clean | not completed in final pass | creates `.grepai/config.yaml` |
| warm indexed state observed | 140 files, 798 chunks, 4.8 MB | not reached | from existing worktree index before clean rerun |
| warm-index status latency | about 0.52s | n/a | `grepai status --no-ui` |
| warm first semantic query | 5.79s | n/a | Beads memory query |
| warm 10-query p50 / p95 | about 5.15s / about 6.78s | n/a | successful semantic calls |
| interrupted clean rerun state | 0 files, 0 chunks | no project initialized | after coordinator stop request |
| empty-index 10-query p50 / p95 | 2.18s / 5.13s | n/a | exits 0 with `[]` |
| foreground/background watch behavior | operationally confusing | n/a | background start can wait 30s and report readiness timeout while watcher exists |
| incremental update | not proven | not proven | stopped before allowing more watch time |

The successful warm-index result is enough to show grepai can work. The stopped
clean rerun is also material: the operational surface makes it easy for an
agent/coordinator to see a long-lived watcher, only `.gitignore` changed, and no
memo progress. That is not acceptable as mandatory first-hop behavior.

## Representative Query Results

Warm-index successful agent-skills run returned relevant results for some
queries:

| Query | Latency | Top result |
|---|---:|---|
| where are Beads memory conventions defined? | 5.79s | `core/beads-memory/SKILL.md` and `docs/BEADS_MEMORY_CONVENTION.md` reference |
| where is semantic mixed-health handled? | 6.42s | weak/noisy Beads health docs |
| where are MCP hydration rules documented? | 5.21s | weak/noisy hydration-related docs |
| where is OpenRouter or embedding provider configured? | 4.93s | weak/noisy `.claude/settings.local.json`, `configs/fleet_hosts.yaml` |
| local government corpus structured source proof cataloged_intent live_proven | 5.09s | unrelated fleet/spec docs |

After the clean rerun was stopped, `grepai status --no-ui` showed:

```text
Files indexed: 0
Total chunks: 0
Index size: 384 B
Last updated: Never
Provider: ollama (nomic-embed-text)
Watcher: not running
```

Ten bounded searches against that empty index still exited `0` and returned
empty JSON arrays. Latencies were:

```text
min 1.136s, p50 2.1785s, p95 5.1284s, max 5.015s
```

This is worse than a hard failure for automation because callers must inspect
both exit status and payload semantics.

## Baseline Comparison

Targeted `rg` / direct reads for the same concepts was immediate and
transparent:

```bash
timeout 10 rg -n "Beads memory conventions|semantic mixed-health|MCP hydration rules|OpenRouter|embedding provider|cataloged_intent|live_proven" docs core extended scripts configs AGENTS.md
```

Representative hits included:

```text
scripts/install-contextplus-patched.sh: OpenRouter embeddings patch
docs/specs/contextplus-openrouter-split-implementation.md: OpenRouter embedding provider config
docs/architecture/2026-04-30-grepai-local-ollama-semantic-bakeoff.md: prior recorded query/failure evidence
```

`rg` is noisy for broad natural-language phrasing, but the user-wait and failure
mode are much better: no daemon, no model, no hidden index, no empty-success
semantic result.

## State, Cache, And Git Behavior

grepai state is project-local:

```text
.grepai/config.yaml
.grepai/index.gob
.grepai/index.gob.lock
```

Watcher logs are outside the worktree:

```text
/home/fengning/.local/state/grepai/logs/grepai-worktree-<hash>.log
```

`.grepai/` must be ignored. `grepai init` appended it to `.gitignore`, which is
the only intentional codebase change besides this memo.

Worktree behavior is acceptable if and only if agents never initialize grepai in
canonical clones. The tool writes local config and index files by design.

## Timeout And Failure Behavior

Good:

- Local Ollama mode avoids code egress.
- Successful warm search returns JSON and relevant semantic hits for some
  documentation questions.
- `grepai watch --stop` stopped the observed background watcher cleanly.

Bad:

- `grepai watch --background` can spend 30s waiting for readiness and return a
  readiness-timeout error while a watcher process continues doing work.
- Foreground `grepai watch --no-ui` is expected to keep running until timeout,
  which is easy for a coordinator to interpret as a stall.
- `grepai status --no-ui` exits successfully with zero indexed files.
- `grepai search --json` exits successfully with `[]` against an empty index
  after spending seconds on query embedding.
- Incremental update behavior was not proven in the final bounded pass.

## Privacy, Cost, And Resource Notes

Local Ollama mode has the right privacy shape: embeddings are sent to
`http://localhost:11434`, not a cloud provider. There is no per-query API cost
after install.

The cost is operational instead:

- every host needs Ollama installed and running;
- every host needs `nomic-embed-text:latest` pulled;
- every worktree needs `.grepai` initialization and a completed index;
- local query embedding still costs roughly 2-6s per query on this host;
- status/readiness needs a wrapper that treats zero files/chunks as not ready.

## Agent Cognitive-Load Assessment

Default critical-path use would increase agent load. The agent has to remember
Ollama readiness, model availability, `.grepai` state, watcher lifecycle,
foreground-vs-background behavior, exit-code-vs-payload checks, and whether the
index is current. That is too much ceremony for "where does X live?" queries
that usually resolve with `rg` and direct reads.

Async/on-demand use is reasonable because the agent can opt into that ceremony
when semantic enrichment is worth the delay.

## Founder HITL-Load Assessment

Founder HITL load would rise if grepai became default now. The coordinator
already had to intervene because the worker appeared stuck on a watcher with
only `.gitignore` changed. That is exactly the type of recurring manual
oversight the routing change is supposed to remove.

Founder load stays low if grepai is documented as optional enrichment behind a
readiness wrapper, not default first-hop routing.

## Decision

**async/on-demand semantic enrichment only**

Do not replace `llm-tldr semantic` with grepai in the canonical default route.
Remove failed semantic first-hop rituals from the default path and use
`rg`/direct reads first. Keep grepai as a possible local enrichment tool after a
future wrapper proves:

- Ollama service active;
- model present;
- `.grepai` initialized in a worktree;
- index has nonzero files/chunks;
- watcher is stopped or known healthy;
- search payload is non-error and non-empty when the task requires a hit.
