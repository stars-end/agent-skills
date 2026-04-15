# Repo Memory Codex Autopilot

**Beads epic:** `bd-s6yjk.9`
**Parent epic:** `bd-s6yjk`
**Primary repo:** `agent-skills`
**Rollout repos:** `agent-skills`, `affordabot`, `prime-radiant-ai`, `llm-common`
**Status:** draft implementation spec
**Decision tier:** T2 workflow architecture
**Date:** 2026-04-15

## Summary

Repo-memory maps are useful only if they stay current without becoming another
founder inbox. The earlier plan centered on deterministic checks and an epyc12
audit loop. After discussion, the desired operating model changed:

- tolerate some documentation churn;
- prefer a competent scheduled agent over manual upkeep;
- keep founder cognitive load near zero;
- avoid a warning-only system that agents ignore;
- avoid blocking ordinary PRs on broad documentation freshness.

This spec adds a Codex autopilot for repo-memory maps. There are two viable
execution modes:

1. GitHub Actions with an `OPENAI_API_KEY` secret.
2. OAuth runner mode using `codex` CLI logged in with ChatGPT on a canonical
   host.

The no-key path is now viable: epyc12 and macmini both passed non-interactive
Codex CLI OAuth smoke tests on 2026-04-15. Therefore the preferred pilot path is
epyc12 as primary OAuth runner, macmini as fallback, and GitHub as the PR/CI
validation surface.

The active contract is narrow: the autopilot may refresh curated repo-memory
docs and approved AGENTS map links, but it must fail closed if it attempts to
modify source code, tests, migrations, dependency files, secrets, or unrelated
workflow/config files.

## Problem

The failure we are fixing is not "agents never saw a warning." Agents saw many
surfaces and still missed the current brownfield map:

- Beads memories and comments were useful but too fragmented for architecture.
- Skills gave workflow guidance but should not contain repo-specific truth.
- AGENTS.md was an index, not a deep architecture map.
- llm-tldr and Serena are verification/edit tools, not durable maps.
- Legacy context-area skills generated repo-local context, but their freshness
  and activation were unreliable.
- Manual map maintenance creates exactly the kind of recurring cognitive load
  this system is meant to remove.

The founder explicitly accepts doc churn if the tradeoff is fresher maps and no
weekly review chore.

## Existing GitHub Actions Audit

Checked on 2026-04-15 across canonical local clones.

### `agent-skills`

Existing workflows:

- `.github/workflows/consistency.yml`
- `.github/workflows/dx-tooling.yml`
- `.github/workflows/test-nightly-dispatch.yml`

Findings:

- No `openai/codex-action` usage.
- No repo-memory refresh workflow.
- `consistency.yml` already runs `scripts/dx-repo-memory-check --repo .
  --base-ref "origin/$BASE_REF"` and the checker regression tests.
- `test-nightly-dispatch.yml` is unrelated dispatch smoke testing and should
  not be merged with repo-memory refresh.

Conclusion: no duplicate autopilot exists. `agent-skills` is the correct pilot
repo.

### `prime-radiant-ai`

Relevant existing workflows:

- `.github/workflows/_context-update.yml`
- `.github/workflows/pr-context-update.yml`
- `.github/workflows/epic-context-update.yml`
- `.github/workflows/dx-audit.yml`

Findings:

- No `openai/codex-action` usage.
- No repo-memory refresh workflow.
- `_context-update.yml` and related callers are legacy context-area skill
  automation. They mutate `.claude/skills/context-*` using Claude Code against
  a Z.ai-compatible endpoint.
- `dx-audit.yml` runs a periodic DX audit using the `agent-skills`
  `dx-auditor` action and writes a report, but it does not maintain repo-owned
  architecture maps.

Conclusion: there is overlap in intent, not in implementation. The new
autopilot must not update `.claude/skills/context-*` and must not be coupled to
the old context-area workflow.

### `affordabot`

Relevant existing workflows:

- `.github/workflows/_context-update.yml`
- `.github/workflows/pr-context-update.yml`
- `.github/workflows/epic-context-update.yml`
- `.github/workflows/dx-audit.yml`
- `.github/workflows/nightly-dispatch.yml`
- `.github/workflows/skill-drift-check.yml`

Findings:

- No `openai/codex-action` usage.
- No repo-memory refresh workflow.
- `_context-update.yml` and related callers mirror the legacy context-area
  pattern from `prime-radiant-ai`.
- `skill-drift-check.yml` is about skills/baseline drift, not repo-memory maps.
- `nightly-dispatch.yml` is unrelated autonomous dispatch.

Conclusion: affordabot should adopt the autopilot only after the
`agent-skills` pilot, and only with subarea maps. Do not duplicate legacy
context-area skill generation.

### `llm-common`

Existing workflows:

- `.github/workflows/_context-update.yml`
- `.github/workflows/dx-pr-metadata.yml`
- `.github/workflows/verify-agents-md.yml`
- `.github/workflows/workflow-syntax.yml`

Findings:

- No `openai/codex-action` usage.
- No repo-memory refresh workflow.
- The repo is small enough that a lightweight profile may be sufficient.

Conclusion: adopt last, with a small-repo exception if the pilot proves the
workflow is too heavy for the codebase.

## Non-Duplicate Boundary

This system is **not** a replacement for every existing context or audit
workflow in the first implementation. It is a new repo-memory maintenance lane
with a deliberately narrow surface.

It must not:

- write `.claude/skills/context-*`;
- regenerate skills;
- rewrite source code;
- update generated baseline artifacts unless the repo explicitly opts in;
- replace `dx-audit`;
- replace `dx-review`;
- run from epyc12 cron as the primary actor.

It may:

- update `docs/architecture/**`;
- update approved map links in `AGENTS.md` or repo-local AGENTS addenda;
- write a repo-memory audit artifact if the repo opts in, for example
  `docs/architecture/.freshness/latest.json`;
- open or update one rolling automation PR;
- auto-merge that PR only under the doc-only exception.

## Architecture

### Ownership Split

GitHub Actions owns:

- weekly and manual repo-memory refresh;
- Codex invocation;
- branch/PR creation or upsert;
- doc-only safety guard;
- artifact upload;
- optional doc-only auto-merge.

epyc12 owns:

- fleet-level monitoring of whether scheduled workflows are green;
- Beads/Dolt health;
- optional Slack or Beads summary;
- no direct documentation edits.

This keeps repo-owned docs maintained by automation while avoiding API-key
setup. The tradeoff is that OAuth runner mode must be made observable enough
that it does not become hidden cron state.

### Execution Mode Decision

#### Mode A: GitHub Actions + API Key

GitHub Actions can run `openai/codex-action@v1`, but current public docs require
an OpenAI API key stored as a GitHub secret. ChatGPT Pro OAuth and the ChatGPT
GitHub connector do not appear to provide a CI-side credential for the action.

Use this mode only if an `OPENAI_API_KEY` exists with a bounded budget.

#### Mode B: OAuth Runner, Preferred Pilot

Use canonical hosts with durable ChatGPT login:

- primary: epyc12
- fallback: macmini

The runner performs the refresh in a disposable worktree, pushes a rolling
branch, and opens or updates the PR with `gh`/GitHub. GitHub Actions then runs
the deterministic guard and normal CI on that PR.

This mode avoids OpenAI API keys and uses the same Codex product auth already
available to interactive agents.

### OAuth Feasibility Evidence

Checked on 2026-04-15:

- epyc12 has `codex-cli 0.120.0`.
- epyc12 `codex login status` reports `Logged in using ChatGPT`.
- epyc12 `systemd-run --user --wait --collect --pipe codex login status`
  succeeds, proving the login is visible from a non-interactive user service.
- epyc12 `systemd-run --user ... codex exec --ephemeral -s read-only -m
  gpt-5.4 -c model_reasoning_effort="low"` returned the exact expected output.
- macmini has `codex-cli 0.120.0`.
- macmini `codex login status` reports `Logged in using ChatGPT`.
- macmini SSH-triggered non-interactive `codex exec --ephemeral -s read-only -m
  gpt-5.4 -c model_reasoning_effort="low"` returned the exact expected output.

This proves both hosts can run Codex from OAuth without a GitHub Actions API key
for the basic model/auth path.

### Runner Hygiene Findings

The smoke tests also found non-blocking hygiene issues:

- epyc12 lacks system `bubblewrap`; Codex falls back to vendored bubblewrap.
  Install OS `bubblewrap` before relying on scheduled sandboxed runs.
- epyc12 has a stale symlink:
  `~/.agents/skills/jules-dispatch -> ~/agent-skills/extended/jules-dispatch`.
- epyc12 and macmini both report invalid legacy core skills missing YAML
  frontmatter:
  - `core/issue-first/SKILL.md`
  - `core/create-pull-request/SKILL.md`
  - `core/beads-workflow/SKILL.md`
  - `core/sync-feature-branch/SKILL.md`

These did not block `codex exec`, but they add noise and should be fixed before
using Codex as unattended infrastructure.

### Flow

1. Checkout full history on default branch.
2. Run deterministic repo-memory scheduled audit.
3. If audit is clean and docs are not age-stale, exit with no diff.
4. In GitHub Actions mode, run `openai/codex-action@v1` using a committed
   prompt. In OAuth runner mode, run `codex exec` from epyc12 in a disposable
   worktree with the same prompt.
5. Codex inspects only the audit report, repo-memory docs, AGENTS routing, and
   source paths needed to verify stale claims.
6. Codex updates only allowed files.
7. Run deterministic guard:
   - reject forbidden file changes;
   - run `dx-repo-memory-check`;
   - run markdown/schema checks available in the repo.
8. If no diff, exit clean.
9. If doc-only diff, open or update a single rolling PR:
   `automation/repo-memory-refresh`.
10. If the repo opts into the auto-merge exception, merge only after all checks
    pass and the guard proves the diff is allowed.
11. If confidence is low or forbidden paths changed, fail closed and update the
    stable repo-memory debt issue instead of opening a normal refresh PR.
12. In OAuth runner mode, if epyc12 fails due to auth/model/sandbox/runtime
    health, retry once on macmini. Do not retry indefinitely.

## Active Contract

### Allowed Files

Default allowed paths:

- `docs/architecture/**`
- `AGENTS.md` only for map-link additions or corrections
- `.github/codex/prompts/repo-memory-refresh.md` only in the implementation PR
- `.github/workflows/repo-memory-refresh.yml` only in the implementation PR
- `scripts/dx-repo-memory-*` only in the implementation PR
- `tests/test-dx-repo-memory-*` only in the implementation PR

For scheduled refresh runs after implementation, allowed paths narrow to:

- `docs/architecture/**`
- `AGENTS.md` map-link changes only

### Forbidden Files

Always forbidden in scheduled refresh output:

- application source code;
- tests;
- migrations;
- dependency manifests and lockfiles;
- secrets or environment files;
- CI workflows;
- scripts;
- skills;
- baseline generated artifacts unless explicitly opted in later.

### Prompt Contract

The committed Codex prompt must instruct the agent to:

- treat `repo-memory-report.json` as the trigger source;
- update only stale or age-expired repo-memory maps;
- cite source paths and commit ranges for every material claim;
- delete or mark uncertain unsupported claims;
- avoid summarizing unrelated code;
- avoid changing executable files;
- output a concise final report with changed docs, evidence paths, and
  confidence.

The prompt must not include untrusted PR text, issue comments, or user-supplied
content from arbitrary events.

### Fallback Contract

epyc12 is the primary OAuth runner because it is the canonical automation host.
macmini is a fallback only when epyc12 fails a preflight or execution step.

Fallback triggers:

- `codex login status` does not report ChatGPT login;
- non-interactive `systemd-run --user` smoke test fails;
- Codex model invocation fails before producing a patch;
- sandbox prerequisite failure prevents execution;
- host unavailable over SSH.

Fallback non-triggers:

- Codex produces a low-confidence report;
- doc-only guard fails;
- repository tests fail;
- PR creation fails due to GitHub permissions.

Those are product/workflow failures, not host-failover failures.

### Auto-Merge Exception

The normal "no auto-merge" rule remains intact for product and tooling code.

Exception:

> Repo-memory refresh PRs may auto-merge only when generated by the approved
> scheduled workflow, the diff is doc-only under allowed paths, all freshness
> and guard checks pass, and no executable/config/source/dependency files
> changed.

This exception is opt-in per repo and can be disabled without changing the
checker.

## Beads Structure

Epic:

- `bd-s6yjk.9` - `Epic: GitHub Actions repo-memory Codex autopilot`

Children:

- `bd-s6yjk.9.1` - `Spec: repo-memory Codex autopilot workflow`
- `bd-s6yjk.9.2` - `Impl: scheduled-audit mode and safety report contract`
- `bd-s6yjk.9.3` - `Impl: Codex refresh prompt and GitHub Actions workflow`
- `bd-s6yjk.9.4` - `Impl: doc-only guard and auto-merge exception`
- `bd-s6yjk.9.5` - `Pilot: agent-skills repo-memory autopilot`
- `bd-s6yjk.9.6` - `Rollout: canonical repo adoption plan`

Dependencies:

- `.9.1` blocks `.9.2` and `.9.4`
- `.9.2` and `.9.4` block `.9.3`
- `.9.3` blocks `.9.5`
- `.9.5` blocks `.9.6`
- existing `bd-s6yjk.5` blocks `.9.2`
- existing `bd-s6yjk.8` blocks `.9.3`

## Validation

### Spec Validation

- Existing workflow audit is recorded.
- Duplicate boundary is explicit.
- GitHub Actions vs epyc12 split is explicit.
- Allowed/forbidden paths are explicit.
- Auto-merge exception is narrow and opt-in.

### Implementation Validation

- `scripts/dx-repo-memory-check --repo . --scheduled-audit --json` or its
  final equivalent emits stable JSON.
- Tests cover clean, stale, waived, missing-doc, age-stale, and forbidden-diff
  cases.
- GitHub workflow syntax validates.
- Prompt is committed under `.github/codex/prompts/`.
- In GitHub Actions mode, workflow runs with `safety-strategy: drop-sudo` and
  `sandbox: workspace-write`.
- In OAuth runner mode, epyc12 preflight checks `codex login status`,
  non-interactive `systemd-run --user`, system `bubblewrap`, `gh auth status`,
  and repo worktree hygiene before invoking Codex.
- OAuth runner mode has a single macmini fallback attempt.
- Neither mode feeds PR comments or arbitrary issue content to Codex.
- Output artifacts include audit report and Codex final message.

### Pilot Validation

- Manual `workflow_dispatch` runs in `agent-skills`.
- Run either exits clean with no diff or produces only allowed doc changes.
- Guard proves doc-only safety.
- No weekly PR spam: use one rolling branch/PR.
- Founder action is required only for low-confidence or forbidden-diff failures.

## Risks

### Doc Churn

Accepted. The system optimizes for fresh maps over perfectly quiet docs.

Mitigation: one rolling branch/PR and doc-only auto-merge exception.

### Confident Nonsense

Primary risk of LLM-written architecture docs.

Mitigation: evidence citation requirement, deterministic stale report, source
path references, and failure on unsupported claims when confidence is low.

### Duplicate Memory Surfaces

The existing context-area workflows could coexist confusingly with repo-memory
maps.

Mitigation: do not update `.claude/skills/context-*`; treat old workflows as
legacy overlap; only deprecate them in a separate explicit migration.

### Hidden Ops State

Running this from epyc12 cron would hide state outside GitHub.

Mitigation: GitHub Actions is the actor; epyc12 only monitors.

## Rollout

1. Harden checker and scheduled-audit report in `agent-skills`.
2. Add doc-only guard and prompt/workflow template.
3. Fix OAuth runner hygiene: system `bubblewrap`, stale skill symlink, and
   legacy skill frontmatter noise.
4. Pilot OAuth runner mode in `agent-skills` from epyc12, with macmini fallback
   disabled first and then enabled.
5. Enable weekly schedule through epyc12 once the PR path is proven.
6. Decide whether doc-only auto-merge exception is enabled for `agent-skills`.
7. Roll to `affordabot` with subarea maps.
8. Roll to `prime-radiant-ai` only after explicitly handling legacy
   context-area workflows and stale architecture docs.
9. Roll to `llm-common` using a small-repo profile or explicit exception.

## Recommended First Task

Start with `bd-s6yjk.9.1`: finalize this spec and review it against the actual
workflow inventory. Implementation should not start until the duplicate
boundary and auto-merge exception are stable.
