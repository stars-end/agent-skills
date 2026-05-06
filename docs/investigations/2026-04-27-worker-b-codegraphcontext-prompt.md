# Worker B Prompt: CodeGraphContext Structural Spike

You are a spike worker agent at a tiny fintech startup. Your job is to benchmark CodeGraphContext as a deterministic structural analysis lane and return evidence, not advocacy.

## DX Global Constraints

1. No writes in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`.
2. Worktree first: `dx-worktree create bd-9n1t2.18 agent-skills`.
3. Open a draft PR after the first real commit.
4. Before done, run `~/agent-skills/scripts/dx-verify-clean.sh`.
5. Final response must include `PR_URL`, `PR_HEAD_SHA`, and `BEADS_SUBTASK: bd-9n1t2.18`.

## Assignment Metadata

- MODE: qa_pass
- BEADS_EPIC: bd-9n1t2
- BEADS_SUBTASK: bd-9n1t2.18
- BEADS_DEPENDENCIES: bd-9n1t2.17
- FEATURE_KEY: bd-9n1t2.18
- CLASS: product
- UPDATE_EXISTING_PR: false
- PR_STATE_TARGET: draft
- REQUIRE_MERGE_READY: false
- SELF_REPAIR_ON_CHECK_FAILURE: true
- FINAL_RESPONSE_MODE: qa_findings

## Required Prior Art

Fetch and read:

```bash
git fetch origin master --prune
git fetch origin pull/592/head:pr-592
git fetch origin pull/593/head:pr-593
git fetch origin pull/594/head:pr-594
```

Read these repo paths from the fetched refs where present:

- `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md`
- `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md`
- `docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md`
- `extended/llm-tldr/SKILL.md`
- `fragments/dx-global-constraints.md`
- `scripts/tldr_contained_runtime.py`
- `scripts/tldr-daemon-fallback.sh`

If a file is missing in a prior-art PR, note it and continue.

## Required Sources

Inspect official docs/source:

- `https://github.com/CodeGraphContext/CodeGraphContext`
- project README/docs from the repo
- any CLI help/manpage output from the installed binary

Use primary sources for claims. Record source URLs in the memo.

## Objective

Answer:

- Can CodeGraphContext replace or demote `llm-tldr` calls, impact, imports, or context?
- Does it avoid live LLM/embedding calls in the critical path?
- How reliable are callers/callees/class/dead-code/complexity queries on real repos?
- How fast is indexing?
- Is state/worktree behavior acceptable?
- Is it simple enough for agents to use without founder babysitting?

## Required Benchmarks

Run against at least:

- `agent-skills`
- `affordabot`
- optionally `prime-radiant-ai` if setup is cheap and safe

Benchmark:

- install time
- index time
- state/cache location
- caller lookup for known symbols
- callee lookup for known symbols
- class hierarchy or module relationship query if supported
- dead code detection if supported
- complexity analysis if supported
- content search behavior
- JSON output behavior
- repeated query latency
- failure legibility

Representative symbols/modules:

- `scripts/tldr_contained_runtime.py`
- `scripts/tldr-daemon-fallback.sh`
- `extended/llm-tldr/SKILL.md`
- one concrete Affordabot service/module discovered from repo docs or source

Compare to bounded `llm-tldr` structural calls where feasible:

```bash
timeout 60 ~/agent-skills/scripts/tldr-daemon-fallback.sh imports --repo <repo> --file <file>
timeout 60 ~/agent-skills/scripts/tldr-daemon-fallback.sh impact --repo <repo> --symbol <symbol>
timeout 60 ~/agent-skills/scripts/tldr-contained.sh context <symbol> --project <repo> --depth 2
```

If a command shape differs, use the documented shape and record the exact command.

## Deliverable

Create:

```text
docs/architecture/2026-04-27-codegraphcontext-structural-spike.md
```

Include:

- setup commands
- timing table
- structural capability table
- comparison to `llm-tldr` structural tools
- no-LLM critical-path assessment
- state/worktree behavior
- failure modes
- agent cognitive load
- founder HITL load
- verdict: replace `llm-tldr` structural, complement `llm-tldr` structural, or reject
- draft PR URL/head SHA

## Done Gate

Do not claim complete until:

- memo exists
- changes are committed and pushed
- draft PR exists
- `~/agent-skills/scripts/dx-verify-clean.sh` passes
- final response includes:

```text
PR_URL: https://github.com/stars-end/agent-skills/pull/<n>
PR_HEAD_SHA: <40-char sha>
BEADS_SUBTASK: bd-9n1t2.18
```

If blocked, return:

```text
BLOCKED: <reason_code>
NEEDS: <single dependency/info needed>
NEXT_COMMANDS:
bdx show bd-9n1t2.18 --json
```
