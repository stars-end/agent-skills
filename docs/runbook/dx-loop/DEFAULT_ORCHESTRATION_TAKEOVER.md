# dx-loop Default Orchestration Takeover Handoff

Status: active
Owner: dx-architecture
Tracking:
- Handoff docs task: `bd-gclh5`
- Follow-up epic: `bd-sighd`
- Next execution task: `bd-sighd.1`

This document is the portable takeover package for the transition that made
`dx-loop` the default agent-facing orchestration surface and demoted
`dx-batch` to a legacy/compatibility/internal substrate.

## Decision

The current policy is:

1. `dx-loop` is the default agent-facing orchestration surface for chained
   Beads work, multi-step outcomes, implement/review baton flow, PR-aware
   follow-up, and "keep going until reviewed or blocked" sessions.
2. `dx-runner` is the lower-level provider runner. Use it directly for provider
   preflight, diagnostics, one-off governed execution, and cases where
   `dx-loop` explicitly points at runner-level state.
3. `dx-batch` remains installed as a legacy/compatibility/internal batch
   substrate. Do not route new agent-facing orchestration work to `dx-batch`
   unless the task is explicitly maintaining compatibility or batch internals.
4. `dx-wave` is an operator/compatibility wrapper, not the preferred agent
   entrypoint.

## Completed Work

The policy change landed in:

- PR: https://github.com/stars-end/agent-skills/pull/577
- Merge commit: `8c6db21f4e131eb0b067bb7c9027ef205e965626`
- Original PR head SHA: `f6990ae17777e1af48ee62910aa64c5846b5552e`
- Beads task: `bd-l48y5`

The merged change updated the canonical generated-policy path and the direct
skill surfaces:

- `fragments/dx-global-constraints.md`
- `AGENTS.md`
- `dist/dx-global-constraints.md`
- `dist/universal-baseline.md`
- `extended/dx-loop/SKILL.md`
- `extended/dx-runner/SKILL.md`
- `extended/dx-batch/SKILL.md`
- `extended/prompt-writing/SKILL.md`
- `scripts/dx-wave`
- `scripts/dx-ensure-bins.sh`
- `@AGENTS.md`
- `docs/architecture/BROWNFIELD_MAP.md`
- `docs/architecture/WORKFLOWS_AND_PATTERNS.md`
- `docs/architecture/DATA_AND_STORAGE.md`
- `docs/architecture/README.md`

Validation at merge time:

- `scripts/dx-repo-memory-check --repo . --base-ref origin/master`: pass
- `git diff --check origin/master..HEAD`: pass
- `bash -n scripts/dx-wave scripts/dx-ensure-bins.sh scripts/publish-baseline.zsh`: pass
- `make check-derived-freshness`: pass
- GitHub CI on PR #577: `derived-freshness`, `lint`, `shell-syntax`, and
  `dx-batch-tests` passed

## Known Context Since PR #577

The repository continued moving after PR #577. Notable context on top of the
merged orchestration policy:

- `dx-review` was changed to remove Claude from the default review quorum.
  Do not reintroduce Claude while touching orchestration docs unless a new
  explicit policy decision says to.
- Repo-memory automation now audits architecture maps and can open doc-only
  freshness PRs. If changing architecture docs, expect the repo-memory gate to
  require adjacent map/index updates.

## Remaining Work For Next Agent

Use `bd-sighd.1` for the next pass. The goal is not to redesign the
orchestration stack; it is to finish the transition cleanup and gather evidence
that agents will now reach for `dx-loop` first.

Recommended scope:

1. Audit long-tail docs and skills for stale phrasing that still teaches
   `dx-batch` as a default/canonical agent-facing orchestrator.
2. Distinguish legitimate lower-level `dx-runner` documentation from stale
   agent-facing orchestration guidance. `dx-runner` remains canonical for
   provider execution; it is just not the default high-level orchestration
   surface for chained work.
3. Preserve compatibility docs for `dx-batch`, but label them clearly as
   legacy/compatibility/internal/operator material.
4. Run at least one low-risk dry-run or smoke check that exercises the
   `dx-loop` first-use path, preferably:
   - `dx-loop status --beads-id bd-sighd.1`
   - `dx-loop explain --beads-id bd-sighd.1`
   - a no-mutation help or diagnostic flow that demonstrates the guidance is
     usable from a fresh agent session
5. Update documentation only where the audit finds real drift. Avoid broad
   rewrites.

Initial files worth checking:

- `docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md`
- `extended/coordinator-dx/SKILL.md`
- `extended/worktree-workflow/SKILL.md`
- `extended/cc-glm/SKILL.md`
- `dispatch/multi-agent-dispatch/SKILL.md`
- `scripts/dx-wave`
- `fragments/dx-global-constraints.md`
- `docs/architecture/BROWNFIELD_MAP.md`
- `docs/architecture/WORKFLOWS_AND_PATTERNS.md`

## Boundaries

Do not:

- delete `dx-batch`
- break compatibility/operator batch paths
- turn every `dx-runner` mention into `dx-loop`
- edit generated artifacts directly without updating their source and running
  the required generator
- use raw 1Password CLI commands for routine secret access
- make product-repo changes as part of this `agent-skills` cleanup

Do:

- keep the hierarchy explicit: `dx-loop` default, `dx-runner` lower-level,
  `dx-batch` legacy/compatibility/internal
- use worktrees for all edits
- use `bdx` for Beads coordination
- use `rg` + direct source reads for discovery, optionally use
  `scripts/semantic-search query` only when status is `ready`, and state a
  tool-routing exception when required routing constraints are hit
- keep changes narrow and merge-ready

## Verification Gates

For any follow-up PR, run the smallest applicable set:

```bash
make publish-baseline
make check-derived-freshness
scripts/dx-repo-memory-check --repo . --base-ref origin/master
git diff --check origin/master..HEAD
bash -n scripts/dx-wave scripts/dx-ensure-bins.sh scripts/publish-baseline.zsh
```

If only docs are changed and `make publish-baseline` produces no semantic
change, reset timestamp-only generated header changes before committing.

## Handoff Prompt

Use `docs/prompts/bd-sighd.1-dx-loop-default-transition.md` as the repo-hosted
prompt source, and fill in the context PR URL/SHA from the handoff PR that
introduced this document.
