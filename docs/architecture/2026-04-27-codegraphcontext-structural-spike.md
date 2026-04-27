# CodeGraphContext Structural Spike (Worker B)

Date: 2026-04-27  
Beads subtask: `bd-9n1t2.18`  
Mode: `qa_pass`

## Scope

Goal: benchmark CodeGraphContext (`cgc`) as a deterministic structural-analysis lane and compare against bounded `llm-tldr` structural calls.

Repos benchmarked:

- `/tmp/agents/bd-9n1t2.18/agent-skills`
- `/tmp/agents/bd-9n1t2.18/affordabot`

## Prior Art + Inputs Read

Fetched:

```bash
git fetch origin master --prune
git fetch origin pull/592/head:pr-592
git fetch origin pull/593/head:pr-593
git fetch origin pull/594/head:pr-594
git fetch origin pull/595/head:coord-bd-9n1t2.17
```

From fetched refs:

- `coord-bd-9n1t2.17:docs/investigations/2026-04-27-worker-b-codegraphcontext-prompt.md`
- `coord-bd-9n1t2.17:docs/investigations/2026-04-27-llm-tldr-two-lane-coordination-plan.md`
- `pr-592`: required docs under `docs/{architecture,investigations}` are missing; `extended/llm-tldr/SKILL.md`, `fragments/dx-global-constraints.md`, `scripts/tldr_contained_runtime.py`, `scripts/tldr-daemon-fallback.sh` are present
- `pr-593` and `pr-594`: all required paths present

## Primary Sources

- GitHub repo: <https://github.com/CodeGraphContext/CodeGraphContext>
- README: <https://github.com/CodeGraphContext/CodeGraphContext/blob/main/README.md>
- `pyproject.toml` (dependency surface): <https://github.com/CodeGraphContext/CodeGraphContext/blob/main/pyproject.toml>
- Docs home: <https://codegraphcontext.github.io/>
- Docs: how it works (Tree-sitter -> graph construction -> graph DB -> querying): <https://codegraphcontext.github.io/CodeGraphContext/concepts/how_it_works/>
- Docs: analysis/querying command surface: <https://codegraphcontext.github.io/CodeGraphContext/reference/cli_analysis/>
- Docs: indexing/management: <https://codegraphcontext.github.io/CodeGraphContext/reference/cli_indexing/>

## Setup Commands (Exact)

```bash
dx-worktree create bd-9n1t2.18 agent-skills
dx-worktree create bd-9n1t2.18 affordabot

TIMEFORMAT='real %3R'; time uv tool install --reinstall codegraphcontext
cgc --help
cgc analyze --help
cgc find --help
cgc analyze callers --help
cgc analyze calls --help
cgc analyze complexity --help
cgc find content --help
cgc index --help
cgc context --help
cgc context list
```

## Timings

Shell timing uses `TIMEFORMAT='real %3R'; time <cmd>` because `/usr/bin/time` is unavailable on this host.

### Install + Index

| Step | Command | Result |
|---|---|---|
| Install | `uv tool install --reinstall codegraphcontext` | `2.761s total` |
| Index (`agent-skills`, global mode) | `cgc index --force /tmp/agents/bd-9n1t2.18/agent-skills` | CGC-reported `18.45s`; shell total `19.689s` |
| Index (`affordabot`, global mode) | `cgc index --force /tmp/agents/bd-9n1t2.18/affordabot` | CGC-reported `115.89s`; shell total `1:56.82` |
| Re-index (`agent-skills`, per-repo probe) | `cgc context mode per-repo && cgc index --force ...` | CGC-reported `13.90s`; shell total `14.896s` |

### Query Latency (Representative)

| Repo | Query | Command | Time |
|---|---|---|---|
| agent-skills | callers | `cgc analyze callers apply_containment_patches --file scripts/tldr_contained_runtime.py` | `0.872s` |
| agent-skills | callees | `cgc analyze calls apply_containment_patches --file scripts/tldr_contained_runtime.py` | `0.900s` |
| agent-skills | dead code | `cgc analyze dead-code` | `0.829s` |
| agent-skills | complexity | `cgc analyze complexity --limit 10` | `0.775s` |
| agent-skills | content search | `cgc find content "semantic_index_missing"` | `0.775s` then `0.873s` repeat |
| affordabot | callers | `cgc analyze callers evaluate_query --file backend/services/discovery/round1_benchmark.py` | `0.779s` |
| affordabot | callees | `cgc analyze calls evaluate_query --file backend/services/discovery/round1_benchmark.py` | `0.752s` |
| affordabot | complexity | `cgc analyze complexity evaluate_query --file backend/services/discovery/round1_benchmark.py` | `0.768s` |
| affordabot | dead code | `cgc analyze dead-code backend/services/discovery/round1_benchmark.py` | `1.002s` |
| affordabot | content search | `cgc find content "OpenRouter"` | `0.859s` then `0.976s` repeat |

## Structural Capability Coverage

| Capability | CodeGraphContext evidence | Result |
|---|---|---|
| Caller lookup | `analyze callers` for `apply_containment_patches` and `evaluate_query` | Works |
| Callee lookup | `analyze calls` for same symbols | Works |
| Class hierarchy | `analyze tree SkillOptimizer`, `analyze tree AutoDiscoveryService` | Works, but sparse/no parents in tested classes |
| Dead code detection | `analyze dead-code` | Works (large result sets) |
| Complexity analysis | `analyze complexity` | Works |
| Module dependency/import relationship | `analyze deps <file>` on tested Python files | Weak in this run (`No dependency information found`) |
| Content search | `find content "..."` | Works as lexical/content search |
| JSON output behavior | `--json` tested on `analyze callers` | Not supported (`No such option: --json`) |

## Bounded `llm-tldr` Structural Comparison (Feasible Commands)

The worker prompt supplied command shapes with `--repo` and `--symbol`; actual helper CLI shape differs. Exact behavior:

### Command shape checks

```bash
~/agent-skills/scripts/tldr-daemon-fallback.sh imports --help
~/agent-skills/scripts/tldr-daemon-fallback.sh impact --help
~/agent-skills/scripts/tldr-daemon-fallback.sh context --help
```

Observed:

- `imports` takes `--file` and optional `--language` (no `--repo`)
- `impact` requires `--function` (not `--symbol`)
- `context` requires `--entry`

### Agent-skills comparison

| Tool | Command | Time | Notes |
|---|---|---|---|
| llm-tldr | `timeout 60 ... imports --file scripts/tldr_contained_runtime.py` | `1.460s` | JSON imports returned |
| llm-tldr | `timeout 60 ... impact --repo ... --function apply_containment_patches` | `0.953s` | Returned `{"callers":[]}` |
| llm-tldr | `timeout 60 ... context --repo ... --entry apply_containment_patches --depth 2` | `7.617s` | Rich structural expansion (~19 functions) |
| cgc | `cgc analyze callers apply_containment_patches --file ...` | `0.872s` | Found 4 callers |
| cgc | `cgc analyze calls apply_containment_patches --file ...` | `0.900s` | Found 5 callees |

### Affordabot comparison

| Tool | Command | Time | Notes |
|---|---|---|---|
| llm-tldr | `timeout 60 ... imports --file backend/services/discovery/round1_benchmark.py` | `1.476s` | JSON imports returned |
| llm-tldr | `timeout 60 ... impact --repo ... --function evaluate_query` | `1.369s` | Returned `{"callers":[]}` |
| llm-tldr | `timeout 60 ... context evaluate_query --project ... --depth 2` | `10.745s` | Structural expansion (~5 functions) |
| cgc | `cgc analyze callers evaluate_query --file ...` | `0.779s` | Found 1 caller (`run_lane_benchmark`) |
| cgc | `cgc analyze calls evaluate_query --file ...` | `0.752s` | Found callees |

## No-LLM Critical Path Assessment

Evidence:

1. CodeGraphContext docs describe a parsing+graph pipeline (`Tree-Sitter` parsing, graph construction, graph DB storage/querying) rather than embedding/vector retrieval in the query path.
2. Upstream `pyproject.toml` dependency list includes graph and parsing dependencies (`neo4j`, `falkordb`, `tree-sitter*`, `fastapi`, etc.) and does not include embedding/LLM runtime libraries such as `sentence-transformers`, `transformers`, or OpenAI SDK dependencies.
3. Local installed package grep for `openai|anthropic|embedding|transformers|ollama` in runtime package paths found only setup-wizard integration-path strings for IDE config locations, not analysis-path dependencies.
4. Runtime query latencies (~0.7-1.0s) are consistent with local graph queries.

Assessment: **CodeGraphContext structural queries avoid live LLM/embedding calls in the tested critical path**.

## State / Worktree Behavior

### Global mode (default)

- `cgc context list` reports `Current Mode: global`.
- State written under: `/home/fengning/.codegraphcontext/`
  - `/home/fengning/.codegraphcontext/.env`
  - `/home/fengning/.codegraphcontext/global/db/falkordb`
  - `/home/fengning/.codegraphcontext/global/db/falkordb.sock`
- No repo-local `.codegraphcontext` directory created in either worktree in global mode.

### Per-repo mode probe

Command:

```bash
cgc context mode per-repo
cgc index --force /tmp/agents/bd-9n1t2.18/agent-skills
```

Observed:

- Auto-created `/tmp/agents/bd-9n1t2.18/agent-skills/.codegraphcontext`
- Also created `.cgcignore` in worktree root
- Mode switched back after probe: `cgc context mode global`

Worktree implications:

- Global mode: safer for write-scope isolation (state outside repo tree).
- Per-repo mode: repo-local artifacts appear and must be cleaned/ignored.

## Failure Legibility

Observed failure/edge responses:

- Unsupported option clarity is good:
  - `cgc analyze dead-code --limit 15` -> `No such option: --limit`
  - `cgc analyze callers ... --json` -> `No such option: --json`
- Query miss clarity is mixed:
  - `analyze deps <file>` frequently returns `No dependency information found` for files that do have imports
- Context targeting in global mode can hide index boundaries:
  - Running `cgc analyze callers foo` in a fresh unindexed dir (`/tmp/bd-9n1t2.18-cgc-unindexed`) returned `No callers found` (not an explicit “repo not indexed” signal)

## Evidence Quality Notes

- All timings are command-level measured with shell `time`.
- All benchmark commands are included verbatim in this memo.
- Two real repos were indexed and queried.
- Bounded `llm-tldr` comparisons used `timeout 60` and actual helper command shapes when prompt shape differed.
- No claims are based on marketing copy alone; all key claims were supported by direct runtime behavior and/or upstream source/docs.

## Agent Cognitive Load + Founder HITL Load

### Agent cognitive load

- Strengths:
  - Single CLI shape for structural operations (`analyze callers/calls/complexity/dead-code`)
  - Fast repeated structural queries
- Weak spots:
  - No JSON output for many CLI operations increases wrapper/parsing burden
  - Global/per-repo context mode creates hidden state assumptions
  - `deps` reliability was weaker than expected in this run

### Founder HITL load

- Low for day-to-day structural tracing once indexed (fast, deterministic, local).
- Medium if rollout requires:
  - policy around global vs per-repo mode
  - wrappers for machine-readable output
  - fallback rules for queries with sparse/ambiguous results

## Verdict

**Verdict: complement `llm-tldr` structural (do not replace outright yet).**

Rationale:

1. CodeGraphContext is strong at deterministic local caller/callee/dead-code/complexity workflows and avoids live embedding/LLM calls in the tested critical path.
2. It is materially faster than bounded `llm-tldr context` expansion queries in these runs.
3. It does not yet cleanly replace `llm-tldr` structural surface for this stack due to:
   - missing machine-friendly JSON options in tested CLI flows
   - inconsistent `deps` utility in these tests
   - context-mode/state behavior that needs policy hardening to avoid confusion/artifact drift

Recommended lane classification:

- **Use as a structural complement lane now** for fast deterministic call graph + dead-code + complexity checks.
- **Keep `llm-tldr` canonical** where broader unified structural+context routing and existing contracts are still required.

## PR Metadata

PR_URL: https://github.com/stars-end/agent-skills/pull/596  
PR_HEAD_SHA: 22770655b9662860784626eb80f9a4b93b76728c
