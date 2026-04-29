# CocoIndex Semantic Recheck Bakeoff

Date: 2026-04-30
BEADS_EPIC: bd-9n1t2.30
BEADS_SUBTASK: bd-9n1t2.30.3
Feature-Key: bd-9n1t2.30.3
Mode: qa_pass
Candidate: cocoindex-code / `ccc`

## Verdict

`reject`

CocoIndex/cocoindex-code should not replace `llm-tldr semantic`, and it should not be promoted even as async/on-demand enrichment in the current routing contract. The prior promising docs/source review did not survive the final runtime recheck: `ccc index` still timed out under the required 120s bound, `ccc search` also timed out, and `ccc doctor` timed out while indexing was stuck.

The observed failure is worse than a normal slow first build because the CLI starts a background daemon, leaves the project in `indexing` state, and `status` reports partial progress without resolving the critical-path command. That increases agent cognitive load and founder HITL load instead of reducing either.

## Prior Evidence Read

Required Beads read:

```bash
bdx show bd-9n1t2.30.3 --json
```

Prior PR refs fetched:

```bash
git fetch origin pull/593/head:pr-593 pull/594/head:pr-594 --prune
```

Prior bakeoff artifacts read from fetched refs:

- `pr-593:docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md`
- `pr-594:docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md`
- `pr-594:docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md`

Relevant prior finding: CocoIndex looked strong in docs and diagnostics, but previous runtime evidence found indexing stuck and search hanging. This recheck specifically tested whether that hang was fixed.

## Official Docs And Source Checked

Source/docs inspected:

- https://github.com/cocoindex-io/cocoindex-code
- https://cocoindex.io/cocoindex-code/
- Installed CLI help from `ccc --help`, `ccc init --help`, `ccc index --help`, `ccc search --help`, and `ccc daemon --help`

Docs claim a simple `pipx install 'cocoindex-code[full]'`, `ccc init`, `ccc index`, `ccc search` workflow. The CLI exposes `init`, `index`, `search`, `status`, `reset`, `doctor`, `mcp`, and `daemon`.

## Environment

- Worktree: `/tmp/agents/bd-9n1t2.30.3/agent-skills`
- Canonical clone writes: none
- Python used by pipx: 3.12.3
- Installed package: `cocoindex-code 0.2.31`
- Installed apps: `ccc`, `cocoindex-code`
- Required repos attempted: `agent-skills`
- `affordabot`: skipped because the required `agent-skills` index/search path was already blocked
- `prime-radiant-ai`: skipped as optional after required path failed

## Setup Commands

```bash
dx-worktree create bd-9n1t2.30.3 agent-skills
cd /tmp/agents/bd-9n1t2.30.3/agent-skills
git fetch origin pull/593/head:pr-593 pull/594/head:pr-594 --prune
time timeout 900 pipx install 'cocoindex-code[full]'
ccc --help
ccc init --help
ccc index --help
ccc search --help
ccc daemon --help
time timeout 120 ccc init
time timeout 120 ccc index
time timeout 120 ccc status
time timeout 120 ccc doctor
time timeout 120 ccc daemon status
time timeout 120 ccc search 'where are Beads memory conventions defined?' --limit 5
timeout 30 ccc daemon stop
```

The install used a 900s timeout because the `[full]` extra can reasonably install local embedding/model dependencies. Runtime commands used the required 120s bound.

## Exact Config Excluding Secrets

Global settings created at `/home/fengning/.cocoindex_code/global_settings.yml`:

```yaml
embedding:
  provider: sentence-transformers
  model: Snowflake/snowflake-arctic-embed-xs
  indexing_params: {}
  query_params:
    prompt_name: query
```

The generated global settings file includes commented examples for cloud provider API keys. No secrets were configured or used.

Project settings created at `.cocoindex_code/settings.yml` included default include/exclude patterns. Important details:

- Excludes dot paths: `**/.*`
- Excludes `.cocoindex_code`
- Includes common code and documentation extensions, including Python, JS/TS, Rust, Go, Java, C/C++, Shell, Markdown, JSON, YAML, TOML, HTML/CSS, and more

## Timing Table

| Step | Command | Result | Time |
|---|---|---:|---:|
| Install | `timeout 900 pipx install 'cocoindex-code[full]'` | PASS, installed 0.2.31 | 1:49.67 |
| CLI version | `ccc --version` | FAIL, no such option | 0.727s |
| CLI help | `ccc --help` | PASS | 0.672s |
| Init | `timeout 120 ccc init` | PASS | 20.475s |
| Index | `timeout 120 ccc index` | FAIL, timed out | 2:00.01 |
| Status | `timeout 120 ccc status` | PASS, partial index visible | 1.962s |
| Doctor | `timeout 120 ccc doctor` | FAIL, timed out | 2:00.03 |
| Daemon status | `timeout 120 ccc daemon status` | PASS, project stuck `indexing` | 1.727s |
| Search | `timeout 120 ccc search 'where are Beads memory conventions defined?' --limit 5` | FAIL, timed out | 2:00.02 |
| Stop daemon | `timeout 30 ccc daemon stop` | PASS | under 30s |

## Status And Doctor Summary

`ccc status` after the timed-out index:

```text
Project: /tmp/agents/bd-9n1t2.30.3/agent-skills
Settings: /tmp/agents/bd-9n1t2.30.3/agent-skills/.cocoindex_code/settings.yml
Index DB: /tmp/agents/bd-9n1t2.30.3/agent-skills/.cocoindex_code/target_sqlite.db
Indexing in progress: 373 files listed | 91 added, 0 deleted, 0 reprocessed, 0 unchanged, error: 0
Index stats:
  Chunks: 752
  Files:  91
  Languages:
    markdown: 476 chunks
    bash: 161 chunks
    python: 72 chunks
    yaml: 28 chunks
    json: 11 chunks
    text: 3 chunks
    toml: 1 chunks
```

`ccc daemon status`:

```text
Daemon version: 0.2.31
Uptime: 157.7s
Projects:
  /tmp/agents/bd-9n1t2.30.3/agent-skills [indexing]
```

`ccc doctor` printed global settings and daemon metadata, then timed out at 120s. It reported daemon version `0.2.31`, one loaded project, and many inherited environment variable names, but did not complete diagnostics.

## Previous-Hang Regression Result

Regression result: not fixed.

`ccc index` still hung under the required 120s timeout. `ccc search` also hung under 120s after the partial index existed. This preserves the prior blocker and makes CocoIndex unsuitable for critical-path semantic discovery.

## Representative Query Results

Only one CocoIndex query was run because the first search timed out:

```bash
time timeout 120 ccc search 'where are Beads memory conventions defined?' --limit 5
```

Result: timeout at 120s with no useful output.

The remaining required representative queries were not run through CocoIndex because indexing/search was already blocked:

- where is semantic mixed-health handled?
- where are MCP hydration rules documented?
- where is OpenRouter or embedding provider configured?
- local government corpus structured source proof cataloged_intent live_proven
- where are Beads memory conventions defined?
- where is Railway auth loaded for agents?
- where is dx-worktree policy documented?
- where are llm-tldr fallback scripts defined?

This is intentional per assignment: if indexing/search still hangs under bounded timeout, stop and document the blocker rather than babysitting indefinitely.

## Baseline Comparison

Targeted `rg`/direct reads:

```bash
time timeout 120 rg -n "semantic.*mixed|mixed.*semantic|mixed-health|hydration|MCP hydration|OpenRouter|embedding provider|Beads memory|dx-worktree|Railway auth|tldr-daemon-fallback|llm-tldr fallback" docs scripts core extended health infra railway dispatch AGENTS.md README.md pyproject.toml
```

Result: useful locations in 0.039s. Examples included:

- `AGENTS.md:354` for Codex desktop MCP hydration checks
- `AGENTS.md:594` and `core/beads-memory/SKILL.md` for Beads memory conventions
- `extended/worktree-workflow/SKILL.md` for dx-worktree policy
- `extended/llm-tldr/SKILL.md` for fallback scripts and timeout rules
- `core/op-secrets-quickref/SKILL.md` and `core/database-quickref/SKILL.md` for Railway/auth handling
- `docs/specs/contextplus-openrouter-split-implementation.md` for OpenRouter embedding provider configuration

Current llm-tldr fallback:

```bash
time timeout 120 bash scripts/tldr-daemon-fallback.sh semantic --repo /tmp/agents/bd-9n1t2.30.3/agent-skills --query 'where are Beads memory conventions defined?'
```

Result: failed legibly in 0.708s with `reason_code: semantic_index_missing` and a concrete fallback recommendation to use targeted `rg`/direct source reads.

```bash
time timeout 120 bash scripts/tldr-daemon-fallback.sh tree --repo /tmp/agents/bd-9n1t2.30.3/agent-skills
```

Result: returned a repo tree in 8.409s.

```bash
time timeout 120 bash scripts/tldr-daemon-fallback.sh search --repo /tmp/agents/bd-9n1t2.30.3/agent-skills --pattern 'Beads memory conventions'
```

Result: `status: ok`, empty results in 14.772s. This is not good, but it completed and did not leave a background indexer running.

## State And Worktree Behavior

CocoIndex writes project-local state under `.cocoindex_code/`:

```text
.cocoindex_code/settings.yml 870 bytes
.cocoindex_code/target_sqlite.db 15478784 bytes
```

The global config is written to:

```text
/home/fengning/.cocoindex_code/global_settings.yml
```

Worktree behavior concern: `ccc init` did not modify `.gitignore` in this worktree, and `.cocoindex_code/` appeared as untracked:

```text
?? .cocoindex_code/
```

That means agents must remember to delete or ignore the cache before commit. This is a cognitive-load regression from a first-hop analysis tool.

The project cache was removed before committing this memo:

```bash
rm -rf .cocoindex_code
```

## Incremental Update Behavior

Not measurable. The first index did not complete under 120s, so there was no valid completed baseline for an incremental update. `ccc status` showed partial progress at 91/373 files and the daemon remained in `indexing` state.

## Failure Modes

- `ccc --version` is unavailable, so exact version must be inferred from `pipx install` output or `ccc doctor` daemon metadata.
- `ccc index` can time out while leaving a daemon running in the background.
- `ccc status` can report partial state, but that does not make search usable.
- `ccc doctor` can time out while indexing is stuck, so the diagnostic surface is not reliable under the failure condition that matters most.
- `ccc search` can hang while indexing is incomplete.
- `.cocoindex_code/` was untracked after init, creating commit hygiene risk.

## Agent Cognitive Load

High. The happy-path CLI is small, but the actual failure path requires the agent to understand daemon lifecycle, partial index state, project-local cache cleanup, missing version output, and when to stop. For a critical-path semantic tool, the right failure behavior is bounded, legible, and immediately actionable. CocoIndex did not meet that bar.

## Founder HITL Load

High. A founder should not need to monitor indexing, decide whether to kill a daemon, teach agents to clean `.cocoindex_code/`, or interpret partial indexing state. The failure mode recreates the same operational burden that motivated the llm-tldr replacement search.

## Critical-Path Suitability

Not suitable.

Critical-path semantic discovery needs one of these outcomes within the bound: useful results, a clear no-result answer, or a precise failure with a fallback. CocoIndex produced a timed-out index and timed-out search.

## Async/On-Demand Enrichment Suitability

Not suitable for the current contract.

An async enrichment lane can tolerate slower indexing, but it still needs reliable completion, restart behavior, and diagnostics. This recheck saw `doctor` time out during the stuck indexing condition, so the tool is not yet safe to hand to agents as unattended enrichment.

## Final Decision

`reject`

CocoIndex/cocoindex-code remains promising on paper, but the current installed version did not fix the runtime blocker. Keep the default fallback as targeted `rg`/direct reads plus any currently working llm-tldr fallback. Do not replace `llm-tldr semantic` with `ccc`, and do not add `ccc` to the default agent routing path.

PR_URL: pending
PR_HEAD_SHA: pending
