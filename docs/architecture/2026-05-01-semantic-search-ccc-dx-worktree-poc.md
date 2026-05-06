# 2026-05-01 Semantic Search (`ccc`) DX Worktree POC

## Status

POC complete. Clean measurements below used non-canonical clones under
`/tmp/semantic-search-poc/bd-9n1t2.30.8/` and isolated `ccc` global state with
`COCOINDEX_CODE_DIR`.

## Problem Statement

Evaluate CocoIndex Code (`ccc`) as an optional semantic-search lane after `llm-tldr` semantic-first removal, under `dx-worktree` workflow:

- Keep `rg`/`fd`/direct reads as first-hop.
- Keep semantic indexing off canonical clones.
- Allow task worktrees to query a canonical-style index surface as hint-only.
- Ensure query path never blocks on indexing.

## Source Context

- PR #603 (`a11e364347dd672d0aeff8b0000c91eacb9fd1ea`)
- PR #606 (`314bb8c0c88fc2df28aed5cffdee25739983d14c`)
- PR #607 (`6ea7957442f6c1d23705296dde1de1f0bb8472b9`)
- PR #608 (`afb612343dd89a825e2130ddcba918f0e358020d`) wrapper evaluated for
  readiness behavior:
  - `scripts/semantic-search`
  - `scripts/semantic_search.py`
  - `docs/semantic-search.md`
  - `tests/test_semantic_search.py`

## Environment and Versions

- `ccc` binary: `/home/fengning/.local/bin/ccc`
- Wrapper execution path: `/usr/bin/python3 scripts/semantic_search.py`
- `ccc` version observed in `doctor`: `0.2.31`
- Embedding provider/model observed in `doctor`:
  `sentence-transformers`, `Snowflake/snowflake-arctic-embed-xs`
- Embedding dimension observed in `doctor`: `384`
- Clean runs used per-run isolated global state:
  - `/tmp/semantic-search-poc/bd-9n1t2.30.8/ready-check-20260501-230609/coco-global`
  - `/tmp/semantic-search-poc/bd-9n1t2.30.8/poc-agent-skills-20260501-230814/coco-global`
  - `/tmp/semantic-search-poc/bd-9n1t2.30.8/poc-affordabot-20260501-231439/coco-global`
  - `/tmp/semantic-search-poc/bd-9n1t2.30.8/poc-prime-radiant-ai-20260501-231842/coco-global`

## Invalid Setup Attempts (Not Product Evidence)

The following are explicitly excluded from conclusions:

- Early runs impacted by missing PATH entries (`ccc` / `python3` resolution failures).
- Early runs impacted by shared default global daemon state (`~/.cocoindex_code`).
- Accidental concurrent `ccc index` attempts on `agent-skills-index`.

These are operational setup mistakes, not `ccc` product behavior evidence.

They are still useful operational lessons: `ccc` uses a daemon, and a bounded
`timeout <N> ccc index` can leave a `ccc run-daemon` process alive. Any agent
automation must stop or kill only the POC/index-surface-scoped daemon after a
timeout.

## Required Measurement Protocol (Isolated Rerun)

For each repo surface under `/tmp/semantic-search-poc/bd-9n1t2.30.8/<repo>-index`:

1. `timeout 60 $CCC daemon stop || true`
2. `timeout 120 $CCC init --force`
3. `timeout 120 $CCC doctor`
4. One bounded `timeout <N> $CCC index`
5. Record exact index exit code and elapsed time
6. `timeout 30 $CCC status`
7. `/usr/bin/python3 $WRAP_PY status --repo <surface>`
8. If not ready: verify fallback:
   - `/usr/bin/python3 $WRAP_PY query --repo <surface> "test query"`
   - Expect: `semantic index unavailable; use rg.`
9. If ready: run representative queries and record latency
10. Stale check by touching tracked file then rerun wrapper status
11. `timeout 60 $CCC daemon stop || true`; if daemon survives, record and kill POC-scoped daemon only

Timeouts:

- `agent-skills`: 300s
- `affordabot`: 300s
- `prime-radiant-ai`: 420s
- `llm-common`: 180s

## Per-Repo Results

### `agent-skills`

| Field | Value |
|---|---|
| Surface | `/tmp/semantic-search-poc/bd-9n1t2.30.8/poc-agent-skills-20260501-230814/repo` |
| Doctor matched files | 856 |
| Index timeout bound | 300s |
| Index exit code | 124 |
| Index elapsed | 300s |
| Raw `ccc search` | timed out at 45s |
| Wrapper status | `indexing` |
| Wrapper query fallback/latency | `semantic index unavailable; use rg.` in 1s |
| Stale behavior | Not reached because index remained `indexing` |
| Daemon cleanup behavior | `ccc daemon stop` cleaned up after timeout |

### `affordabot`

| Field | Value |
|---|---|
| Surface | `/tmp/semantic-search-poc/bd-9n1t2.30.8/poc-affordabot-20260501-231439/repo` |
| Doctor matched files | 945 |
| Index timeout bound | 300s |
| Index exit code | 0 |
| Index elapsed | 207s |
| Raw `ccc search` | relevant RAG hits in 1s |
| Wrapper status | `stale` due wrapper freshness bug |
| Forced-ready wrapper query | relevant RAG hits in 2s |
| Stale behavior | Dirty tracked file reported as non-ready |
| Daemon cleanup behavior | `ccc daemon stop` succeeded |

### `prime-radiant-ai`

| Field | Value |
|---|---|
| Surface | `/tmp/semantic-search-poc/bd-9n1t2.30.8/poc-prime-radiant-ai-20260501-231842/repo` |
| Doctor matched files | 2,277 |
| Index timeout bound | 420s |
| Index exit code | 124 |
| Index elapsed | 420s |
| Raw `ccc search` | timed out at 45s |
| Wrapper status | `indexing` |
| Wrapper query fallback/latency | `semantic index unavailable; use rg.` in 2s |
| Stale behavior | Not reached because index remained `indexing` |
| Daemon cleanup behavior | `ccc daemon stop` succeeded |

### `llm-common`

| Field | Value |
|---|---|
| Surface | `/tmp/semantic-search-poc/bd-9n1t2.30.8/ready-check-20260501-230609/llm-common-index` |
| Doctor matched files | 218 |
| Index timeout bound | 180s |
| Index exit code | 0 |
| Index elapsed | 52s |
| Raw `ccc search` | relevant OpenRouter hits in 11s |
| Wrapper status | `stale` due wrapper freshness bug |
| Forced-ready wrapper query | relevant OpenRouter hits in 1s |
| Stale behavior | Dirty tracked file reported as non-ready |
| Daemon cleanup behavior | `ccc daemon stop` succeeded |

## Wrapper Behavior Matrix

| Repo | ready | indexing | missing | stale | Fallback exact text |
|---|---:|---:|---:|---:|---|
| agent-skills | No | Yes | Not tested | Not reached | `semantic index unavailable; use rg.` |
| affordabot | Only when DB mtime forced newer | No | Not tested | Yes | `semantic index unavailable; use rg.` |
| prime-radiant-ai | No | Yes | Not tested | Not reached | `semantic index unavailable; use rg.` |
| llm-common | Only when DB mtime forced newer | No | Task worktree reports `missing` | Yes | `semantic index unavailable; use rg.` |

## Wrapper Bug Found

PR #608's wrapper is safe but too pessimistic. It classifies readiness by:

1. running `git status --porcelain --untracked-files=no`;
2. comparing `.cocoindex_code/target_sqlite.db` mtime against `.git/index`,
   `.git/HEAD`, and the current ref.

In live tests, the `git status` call itself can update `.git/index` after the
`ccc` DB was written. That makes a freshly indexed clean repo look `stale`.
Forcing `target_sqlite.db` into the future made wrapper queries succeed, proving
the stale result is wrapper logic, not missing ccc search capability.

Fix direction: do not use `.git/index` mtime as a freshness source. Prefer an
explicit metadata file recorded by the index refresh job:

- repo path
- git HEAD SHA at refresh
- dirty-state policy
- index started/finished timestamps
- ccc exit code
- matched/indexed file counts

Then `semantic-search status --repo <worktree>` can resolve to the canonical
index surface and compare worktree HEAD to the recorded indexed HEAD.

## Worktree Hint-Only Strategy

Use `ccc` as a warmed semantic hint lane, not as a live lookup dependency.

Recommended durable layout:

```text
~/.cache/agent-semantic-indexes/
  agent-skills/
    repo/                  # non-canonical clone or worktree
    state.json             # refresh metadata
  affordabot/
    repo/
    state.json
  prime-radiant-ai/
    repo/
    state.json
  llm-common/
    repo/
    state.json
```

Agent query flow from a task worktree:

1. Resolve `/tmp/agents/<beads-id>/<repo>` to the durable index surface.
2. Run `semantic-search status --repo <task-worktree>`.
3. If status is `ready`, query the index surface and label results as
   `semantic hints from indexed HEAD <sha>`.
4. If status is `missing`, `indexing`, or `stale`, return immediately:
   `semantic index unavailable; use rg.`
5. Never run `ccc index` from an agent's default lookup loop.

Refresh flow:

1. A scheduled or explicit command updates the durable index clone from
   `origin/master`.
2. It runs `ccc init --force` once and commits the local `.gitignore` change in
   the index surface only.
3. It runs bounded `ccc index` with `COCOINDEX_CODE_DIR` isolated per repo or
   per refresh job.
4. It writes `state.json` only after successful completion.
5. It stops the repo-scoped daemon and kills only repo-scoped stragglers if
   `timeout` interrupted indexing.

## Global State / Egress Observations

- `COCOINDEX_CODE_DIR` works and moves `global_settings.yml` and daemon logs
  out of `~/.cocoindex_code`.
- `ccc` still starts a daemon per isolated environment. Timeout wrappers do not
  guarantee daemon cleanup.
- The tested install used local SentenceTransformers embeddings. No OpenRouter
  or cloud embedding key was required for these measurements.
- First use may need model/cache availability. This POC ran on a host where the
  local model path was already usable.

## Recommendation

Decision: `DEFER_TO_P2_PLUS` for replacing `llm-tldr` semantic with `ccc` as a
fleet-default tool, but keep `ALL_IN_NOW` for removing `llm-tldr` from default
routing.

Rationale:

- `ccc` is useful when warmed: `affordabot` and `llm-common` produced relevant
  semantic results in 1-11s after successful indexing.
- `ccc` is not a safe live replacement path: `agent-skills` and
  `prime-radiant-ai` timed out on initial indexing and search under bounded
  test conditions.
- The wrapper contract is correct in spirit but needs a metadata-based readiness
  fix before agents can rely on `ready`.
- The founder/agent cognitive-load target is still best served by:
  `rg`/direct reads first, optional semantic hints only when already ready.

## Operationalization Next Steps

1. Fix wrapper freshness to use explicit refresh metadata instead of `.git/index`
   mtime.
2. Add a resolver for `dx-worktree` path -> durable index surface path.
3. Add `semantic-search refresh --repo-name <name>` as an explicit/scheduled
   operation, never called by default query.
4. Add daemon cleanup guard around refresh timeouts.
5. Add focused tests for:
   - ready after a successful refresh;
   - task worktree missing index;
   - task worktree ahead of indexed HEAD;
   - dirty task worktree;
   - timeout leaves no blocking query path.

## Fast Robust Strategy for `dx-worktree`

Minimum viable integration:

```bash
# Query from a task worktree.
semantic-search status --repo /tmp/agents/<beads-id>/<repo>

# Only if ready:
semantic-search query --repo /tmp/agents/<beads-id>/<repo> "natural language query"

# Otherwise:
rg ...
```

Implementation detail: `semantic-search` should not look for `.cocoindex_code`
inside the task worktree. It should map the task worktree repo name to a durable
index surface, read `state.json`, and query that surface. Task worktree edits are
handled by `rg` and direct reads; semantic results are only canonical-HEAD hints.
