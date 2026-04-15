# Repo Memory Freshness Contract

**Beads epic:** `bd-s6yjk`  
**Primary repo:** `agent-skills`  
**Canonical repos in rollout:** `agent-skills`, `affordabot`, `prime-radiant-ai`, `llm-common`  
**Status:** draft after first dx-review pass  
**Decision tier:** T2 architecture proposal before implementation  
**Date:** 2026-04-15

## Summary

The current agent memory stack has several useful surfaces, but no enforced
repo-owned brownfield map contract. That is why repeated agents can miss large
existing subsystems even after Beads memory, skills, AGENTS.md, llm-tldr, and
Markdown research artifacts exist.

This plan establishes one canonical truth surface per knowledge type:

- repo-owned Markdown maps are the canonical curated map of current codebase
  architecture, data flows, and implementation patterns;
- Beads KV is a short cross-session pointer and reminder layer;
- Beads structured memory is for durable decisions and gotchas with provenance;
- AGENTS.md is the routing/index surface that points to repo maps;
- skills enforce workflow, not repo-specific truth;
- llm-tldr verifies map claims against source code;
- Serena performs symbol-aware edits after source verification.

The plan intentionally avoids making one more memory system. It creates
freshness checks around the docs so docs do not become another stale context-area
artifact.

## Review Status

First `dx-review` pass:

- Claude/Opus completed and returned `approve_with_changes`, score `74`.
- cc-glm passed preflight but failed during execution with a Z.ai `429` rate
  limit. This is a dx-review/tooling availability issue, not a spec finding.

Accepted review changes in this revision:

- Phase 3 generated docs are now `DEFER_TO_P2_PLUS` and narrowly scoped.
- Waiver format is explicit and machine-parseable.
- Doc update protocol is explicit.
- Frontmatter required fields are reduced for bootstrap.
- Brownfield-map-first triggers are narrowed.
- Dispatch-order warning added because existing child IDs are historical.
- epyc12 audit cooldown/noise controls added.
- `AGENTS.local.md` versus compiled `AGENTS.md` parsing is specified.

## Initial Problem

The failure mode surfaced during the Affordabot pipeline architecture work:

1. Multiple agents repeatedly rediscovered pieces of the existing pipeline.
2. Prior economic-analysis research, pipeline code maps, and review artifacts
   existed, but were scattered across Markdown files, Beads comments, Beads KV,
   skills, review PRs, and session summaries.
3. The active agent did not have one obvious first stop for "what already exists
   in this repo?"
4. The old context-area skill approach recognized the need for quick codebase
   maps, but it created hidden repo-local skills whose activation and freshness
   were unreliable.
5. Existing root docs proved the same staleness risk: for example,
   `prime-radiant-ai/ARCHITECTURE.md` contains a prominent warning that large
   Supabase sections are outdated after the Railway migration.

The underlying problem is not lack of memory surfaces. The problem is lack of a
single maintained map with deterministic freshness signals and review gates.

## Comprehensive Audit

### Beads / bdx Runtime

Audited files:

- `/Users/fning/beads/cmd/bd/memory.go`
- `/Users/fning/beads/cmd/bd/kv.go`
- `/Users/fning/beads/cmd/bd/prime.go`
- `/Users/fning/agent-skills/core/beads-memory/SKILL.md`
- `/Users/fning/agent-skills/docs/BEADS_MEMORY_CONVENTION.md`

Findings:

- `bd remember` stores memory as KV under `kv.memory.<key>`.
- `bd memories` lists config/KV entries with the `kv.memory.` prefix.
- `bd recall` retrieves one `kv.memory.<key>` entry.
- `bd prime` injects those memories into session context.
- The active runtime at `~/.beads-runtime/.beads` is only local config,
  credentials, and runtime pointers. Durable state lives in the shared Dolt
  server database `beads_bd` at `100.107.173.83:3307`.
- `bdx memories --json` currently returns a small number of useful pointer
  memories, including the Affordabot brownfield-map pointer.
- `bdx search memory --label memory --status all` currently also returns active
  `bd-s6yjk.*` planning tasks because they use the `memory` label. This pollutes
  the structured-memory search surface.
- Historical structured memory issues such as `bd-q0f7s` and `bd-q6o1p` do not
  fully carry the required `mem.*` metadata.

Implication:

Beads memory is reliable as a cross-VM pointer and provenance layer. It is not a
good primary store for long-form architecture maps because it is string-KV,
harder to review with code, and does not naturally model stale-if source paths.

### llm-tldr

Audited files:

- `/Users/fning/agent-skills/extended/llm-tldr/SKILL.md`
- `agent-skills` generated baseline references to the V8.6 routing contract

Findings:

- llm-tldr is the canonical tool for semantic discovery, static analysis,
  call-path/slice/impact tracing, and source verification.
- It is filesystem-local and can analyze a project path directly.
- It is a verification engine, not durable memory.

Implication:

Repo memory docs should cite what to verify, while llm-tldr should verify the
current code before acting on those docs.

### Serena

Audited files:

- `/Users/fning/agent-skills/extended/serena/SKILL.md`
- old context-area skill references to Serena symbol indexing

Findings:

- Serena is appropriate for symbol-aware edits, references, and file-level
  symbol overviews.
- Serena memories are not the canonical cross-VM durable memory layer.

Implication:

Serena should support precise maintenance of maps when symbols move, but should
not own the maps.

### AGENTS.md

Audited files:

- `/Users/fning/agent-skills/scripts/publish-baseline.zsh`
- `/Users/fning/agent-skills/scripts/compile_agent_context.sh`
- `/Users/fning/agent-skills/docs/AGENTS_MD_COMPILATION_GUIDE.md`
- `/Users/fning/prime-radiant-ai/AGENTS.local.md`
- `/Users/fning/affordabot/AGENTS.local.md`

Findings:

- AGENTS.md is the best always-visible routing surface.
- It is not the right place for large architecture documents.
- `compile_agent_context.sh` currently merges global AGENTS.md plus
  `AGENTS.local.md`, but the richer context-skill-routing idea is incomplete.

Implication:

AGENTS.md should contain short required links and rules:

- "For brownfield architecture/data/pipeline work, read these docs first."
- "If changed paths match doc `stale_if_paths`, update docs or waive."

### Skills

Audited files:

- `/Users/fning/agent-skills/search/area-context-create/SKILL.md`
- `/Users/fning/agent-skills/search/context-database-schema/SKILL.md`
- `/Users/fning/agent-skills/search/docs-create/SKILL.md`
- `/Users/fning/agent-skills/extended/context-plus/SKILL.md`
- `/Users/fning/agent-skills/extended/dx-review/SKILL.md`

Findings:

- The old `area-context-create` skill generated repo-local
  `.claude/skills/context-*` files from `.context/area-config.yml`.
- It solved quick navigation but did not solve durable architecture truth.
- It depended on skill activation and manual regeneration.
- Context+ was removed from the canonical fleet contract because of worktree
  blindness, single-root binding, cross-repo overhead, and low usage.
- dx-review exists as a review quorum wrapper and can enforce repo-memory
  compliance in review prompts.

Implication:

The useful part of context-area skills is the workflow pattern:
"force agents to consult a map first." The harmful part is storing repo truth in
skills. The new design keeps the workflow in a canonical skill and puts the
truth in repo-owned docs.

### Markdown Docs

Audited examples:

- `/Users/fning/prime-radiant-ai/ARCHITECTURE.md`
- `/Users/fning/prime-radiant-ai/PATTERNS.md`
- `/Users/fning/affordabot/docs/architecture/...`
- `/Users/fning/agent-skills/docs/BEADS_MEMORY_CONVENTION.md`

Findings:

- Markdown is reviewable, diffable, linkable, and local to the source repo.
- Markdown can still go stale.
- Existing docs lack a uniform freshness contract.

Implication:

Markdown docs should be canonical maps only if paired with deterministic
frontmatter, stale-if checks, generated inventories, and dx-review gates.

## Current Memory-Adjacent Landscape

| Surface | Current role | Strength | Failure mode | New contract |
| --- | --- | --- | --- | --- |
| Beads KV | Short durable facts via `bdx remember` | Cross-VM and prime-injected | Too flat for architecture | Pointers only |
| Beads issues labeled `memory` | Structured durable memory | Provenance and comments | Polluted by active tasks; missing metadata | Closed decision/gotcha records only |
| Beads comments | Task chronology | Good local history | Hard to discover globally | Task-local unless promoted |
| llm-tldr | Semantic/static verification | Verifies code now | Not durable memory | Required verifier for maps |
| Serena | Symbol-aware edits | Precise changes | Not shared memory | Edit support only |
| AGENTS.md | Agent routing | Always visible | Too large if abused | Link/index only |
| Canonical skills | Workflow instructions | Enforces process | Can hide repo truth | Workflow only |
| Context-area skills | Repo-local navigation | Fast entry points | Activation/staleness drift | Deprecated as truth store |
| Repo `.md` docs | Existing docs and maps | Reviewable with code | Stale without gates | Canonical curated map with freshness contract |

## Proposed Solution

### One Truth Per Knowledge Type

The target split:

```text
source code
  final runtime truth

repo docs
  curated map of architecture, data, storage, patterns, and brownfield areas

generated repo docs
  mechanical inventories derived from source

AGENTS.md
  session-visible router to canonical docs and freshness rules

Beads KV
  cross-session pointer to canonical docs

Beads structured memory
  closed, provenance-bearing durable decisions/gotchas

skills
  workflow enforcement and reusable process

llm-tldr / Serena
  verification and edit tools
```

### Required Repo Map Files

Each canonical repo must have either the standard docs or an explicit exception.

For simple repos:

```text
ARCHITECTURE.md
DATA.md
PATTERNS.md
```

For complex repos:

```text
docs/architecture/README.md
docs/architecture/data.md
docs/architecture/patterns.md
docs/architecture/generated/*.md
```

Affordabot should use the complex pattern because pipeline, storage, Windmill,
evidence packages, and economic analysis are too large for one root file.

### Required Frontmatter

Every canonical map doc must include:

```yaml
---
status: active
owner: dx
last_verified_commit: <git-sha>
last_verified_at: YYYY-MM-DD
stale_if_paths:
  - backend/services/pipeline/**
  - backend/schemas/**
---
```

`last_verified_commit` means the curated map was checked against code as of
that commit. It does not mean all generated inventories are current.

Optional frontmatter fields:

```yaml
verification:
  - llm-tldr
  - human-or-agent-review
generated_inventory:
  - docs/architecture/generated/pipeline-inventory.md
beads_memory_keys:
  - affordabot-pipeline-brownfield-map
```

These optional fields should become required only after the checker/audit loop
proves they catch real failures without adding excessive maintenance cost.

### Doc Update Protocol

When `dx-repo-memory-check` marks a map stale, agents must use one of three
outcomes:

1. **Verify-only bump.** Use when code paths matched `stale_if_paths`, but the
   existing map claims are still correct after inspection. The agent must verify
   the relevant claim with source inspection or llm-tldr, then update
   `last_verified_commit` and `last_verified_at`.
2. **Content update.** Use when code changes invalidate or materially alter the
   map. The agent must update the curated prose, update any affected
   `stale_if_paths`, then update `last_verified_commit` and `last_verified_at`.
3. **Waiver.** Use when a touched path matches `stale_if_paths` but the change is
   intentionally irrelevant to the map, such as whitespace-only edits,
   generated-code churn, or a narrow test fixture change.

The brownfield-map-first skill should guide agents through this protocol before
allowing an architecture/brownfield task to claim completion.

### Waiver Format

Waivers must be explicit, grep-able, and machine-parseable. The initial contract
supports two equivalent locations:

Commit trailer:

```text
Repo-Memory-Waiver: <doc path> :: <reason>
```

PR body or local waiver block:

```markdown
<!-- repo-memory-waiver: docs/architecture/pipeline.md :: reason -->
```

Rules:

- `<doc path>` must be a repo-relative Markdown path.
- `<reason>` must be non-empty and at least 20 characters.
- The checker should reject generic reasons such as `n/a`, `not needed`, or
  `no impact`.
- Waivers are valid only for the current changeset. They do not update
  `last_verified_commit`.

### Generated Docs

Decision: `DEFER_TO_P2_PLUS` for committed generated docs until the checker and
pilot prove the curated-map contract works.

Reason:

llm-tldr already provides on-demand tree, structure, call, import, and
architecture analysis for many mechanical inventory questions. Committed
generated docs can recreate the same stale-file-list problem that made
context-area skills expensive.

Generated docs are allowed only when they provide value that on-demand llm-tldr
does not cover well, such as:

- cross-repo inventory summaries;
- deployment topology inventories;
- stable public endpoint matrices used by CI or reviewers;
- stale-if coverage reports.

If implemented, generated docs are limited to mechanical content:

- file inventory;
- endpoint inventory;
- schema/table inventory;
- test map;
- call graph summary;
- stale-if match report.

Generated docs should live under:

```text
docs/architecture/generated/
```

The generator must not rewrite curated prose except inside explicit generated
blocks if a repo chooses block-level generation.

### New Commands

Implement four commands/scripts in `agent-skills`:

```bash
dx-repo-memory-check
dx-repo-memory-audit
dx-regen-docs
dx-repo-memory-report
```

#### dx-repo-memory-check

Fast deterministic checker for local agents and CI.

Responsibilities:

- parse map doc frontmatter;
- validate required fields;
- validate map links in `AGENTS.local.md` when present, falling back to compiled
  `AGENTS.md`;
- validate Beads KV pointer keys are referenced;
- compare changed paths against `stale_if_paths`;
- require doc update, generated inventory refresh, or explicit waiver.
- validate `Repo-Memory-Waiver` trailers or `repo-memory-waiver` PR/body blocks.

Non-responsibilities:

- no LLM calls;
- no Beads mutation;
- no auto-regeneration of curated prose.

#### dx-repo-memory-audit

Daily epyc12 audit loop.

Responsibilities:

- inspect canonical repos read-only;
- run `dx-repo-memory-check --audit`;
- verify Beads KV pointers point to existing docs;
- verify structured memory records use `mem.*` metadata;
- open/update Beads issues for stale or missing maps;
- write reports to `~/.dx-state/repo-memory/reports/`.

Non-responsibilities:

- no direct canonical repo mutation;
- no automatic GitHub PR creation by default;
- no automatic narrative doc rewrite.

#### dx-regen-docs

Controlled mechanical documentation generation. This is explicitly
`DEFER_TO_P2_PLUS` until `dx-repo-memory-check` and at least one canonical repo
pilot are working.

Responsibilities:

- generate `docs/architecture/generated/*.md`;
- support area-specific regeneration, e.g. `--area pipeline`;
- produce deterministic output;
- mark generated docs with source commit and command.

Non-responsibilities:

- no curated architecture prose generation;
- no unreviewed commits.

#### dx-repo-memory-report

Human/agent status summary.

Responsibilities:

- summarize latest epyc12 audit status;
- list stale docs and responsible Beads items;
- show missing AGENTS links or Beads pointers;
- provide next recommended command.

### Canonical Skill

Add a canonical workflow skill:

```text
extended/brownfield-map-first/SKILL.md
```

Trigger examples:

- brownfield;
- repo map;
- brownfield map;
- repo memory;
- stale map;
- existing codebase;
- "are we duplicating";
- "trace the whole path";
- "what already exists".

Avoid generic triggers such as only "architecture", "pipeline", "storage", or
"data flow". Those should normally route first to llm-tldr or the relevant
domain skill. Brownfield-map-first should activate when the task is explicitly
about existing-codebase understanding, duplicate avoidance, repo maps, or
architecture-level change.

The skill must enforce this order:

1. Read repo AGENTS.md for map links.
2. Read the canonical repo maps.
3. Check Beads KV for pointer memories.
4. If relevant code paths changed, check stale-if status.
5. Verify non-trivial claims with llm-tldr.
6. Use Serena only for symbol-aware edits after verification.
7. If implementation changes mapped areas, update docs or add a waiver.

The skill must not contain repo-specific architecture truth.

### AGENTS.md Contract

Each canonical repo's AGENTS.md must include a short section:

```markdown
## Repo Memory

For architecture, data, storage, pipeline, frontend read-model, infra, or
brownfield work, read these before proposing changes:

- docs/architecture/README.md
- docs/architecture/data.md
- docs/architecture/patterns.md

If touched files match doc `stale_if_paths`, update the doc or include a
repo-memory waiver in the PR.
```

For repos using `AGENTS.local.md`, the local file should own these links and
the generated AGENTS.md should include them.

### Beads Memory Contract

Beads KV keys should be short pointers:

```text
repo-affordabot-architecture-map:
Start at docs/architecture/README.md before changing pipeline/search/storage/
economic analysis. Stale-if paths are declared in the docs.
```

Structured memory should be closed issues only. Active project-management issues
must not use the bare `memory` label; use labels such as `repo-memory`,
`memory-system`, or `brownfield` instead.

## Minimizing Overlapping Memory Surfaces

This design reduces overlap by assigning one responsibility to each surface.

What is eliminated:

- repo-specific architecture facts in canonical skills;
- long architecture summaries in Beads KV;
- context-area skills as source of truth;
- AGENTS.md as a long architecture document;
- Serena memories as shared durable truth.

What remains:

- one curated map in repo docs;
- one cross-agent pointer in Beads KV;
- one workflow skill that tells agents how to find and verify the map.

The allowed duplication is only pointer duplication. Narrative duplication is
not allowed.

## Minimizing Agent Confusion

The new default path for brownfield work is deterministic:

```text
AGENTS.md -> repo map docs -> Beads pointer -> llm-tldr verification -> edit
```

Agents no longer need to decide between:

- old context-area skill;
- Beads comments;
- scattered research docs;
- local .serena memory;
- prior session summary.

The skill and AGENTS.md should explicitly say:

"If these disagree, source code wins; repo docs are the maintained map; Beads is
a pointer."

## Minimizing Maintenance Cost and Complexity

Maintenance cost is controlled by:

- small required doc set;
- deterministic stale-if matching;
- generated mechanical inventories only;
- no daily auto-rewrite of curated docs;
- epyc12 daily audit that creates issues instead of mutating repos;
- dx-review checks instead of bespoke review behavior per repo.

The long-term burden is front-loaded: create maps once, then use path-based
freshness gates to keep them honest.

## Minimizing Founder Cognitive Load

The founder should not need to remember where the repo map lives or manually
police stale docs.

Founder-facing behavior:

- agents automatically check the map first;
- stale map issues appear in Beads;
- PR reviewers flag missing doc updates;
- `dx-repo-memory-report` gives one status surface;
- no daily founder review of generated docs;
- no manual monitoring after dev/staging changes.

Decision policy:

- `ALL_IN_NOW` for the repo-memory contract because it removes recurring
  rediscovery tax across canonical repos.
- `DEFER_TO_P2_PLUS` for fully automated narrative doc generation.
- `CLOSE_AS_NOT_WORTH_IT` for resurrecting context-area skills as truth stores.

## Implementation Plan

### Phase 0: Correct Current Beads Plan Hygiene

Beads:

- `bd-s6yjk`
- Blocks all implementation tasks.

Tasks:

- relabel active planning issues away from bare `memory`;
- reserve `memory` label for closed durable memory records;
- add `mem.*` metadata requirement to acceptance criteria;
- add this spec path to the epic via `--spec-id` if supported by current Beads
  conventions.

Acceptance:

- `bdx search memory --label memory --status all` returns only durable memory
  records or documented historical exceptions;
- active repo-memory project tasks use `repo-memory`/`memory-system`, not bare
  `memory`.

### Phase 1: Spec and Review

Beads:

- `bd-s6yjk.3`: Spec: repo-owned brownfield memory contract.

Tasks:

- land this spec in `docs/specs/`;
- run `dx-review` architecture quorum on the plan;
- integrate reviewer findings into the Beads epic;
- capture a short Beads KV pointer to the approved repo-memory contract.

Acceptance:

- spec exists and covers all required user concerns;
- dx-review has 2-provider success or an explicit failure exception with logs;
- reviewer findings are either accepted into the plan or documented as rejected.

### Phase 2: Checker Contract

Beads:

- New child: `bd-s6yjk.5` - `Impl: dx-repo-memory-check`.

Tasks:

- implement frontmatter parser;
- implement required-doc discovery;
- implement AGENTS.md link validation;
- implement `stale_if_paths` matching against changed files;
- implement waiver format validation;
- provide JSON and human output;
- add tests with fixtures.

Acceptance:

- `dx-repo-memory-check --repo <path> --json` reports pass/fail;
- changed path matching a map doc stale-if path fails unless doc changed or
  waiver provided;
- missing `last_verified_commit` fails;
- missing AGENTS link fails;
- no network, no secrets, no LLM calls.

### Phase 3: Mechanical Regeneration

Beads:

- New child: `bd-s6yjk.6` - `Impl: dx-regen-docs mechanical inventories`.

Status:

- `DEFER_TO_P2_PLUS`.
- Do not dispatch until `bd-s6yjk.5` and at least one canonical repo pilot prove
  committed generated docs are worth the maintenance cost.

Tasks:

- define generated docs schema;
- generate only inventories not already well covered by llm-tldr on-demand
  tooling;
- prefer cross-repo or CI-consumed inventories over per-file area listings;
- add generated header with command, source commit, and timestamp;
- ensure output is deterministic enough for CI.

Acceptance:

- generated docs are under `docs/architecture/generated/`;
- generated docs do not modify curated prose;
- running the command twice without source changes yields clean diff.

### Phase 4: epyc12 Audit Loop

Beads:

- New child: `bd-s6yjk.7` - `Impl: epyc12 repo-memory audit loop`.

Tasks:

- implement `dx-repo-memory-audit`;
- inspect canonical repos read-only;
- check Beads KV pointer validity;
- write JSON/Markdown reports under `~/.dx-state/repo-memory/reports/`;
- create or update Beads issues for stale docs;
- add cron/systemd schedule on epyc12 after validation.
- suppress duplicate noise by keying stale-map issues by repo + doc path +
  stale path family.
- do not re-flag a doc when `last_verified_commit` is within a configurable
  recent-commit window, default `5` commits, unless the exact same stale path
  family changes again after verification.

Acceptance:

- dry-run works locally;
- epyc12 run writes latest report;
- missing/stale maps produce Beads issues without mutating canonical repos;
- audit is idempotent for existing open stale-map issues.
- audit does not create repeated issues for recently verified docs.

### Phase 5: Brownfield-Map-First Skill

Beads:

- `bd-s6yjk.2`: Skill: brownfield map first workflow.

Tasks:

- create `extended/brownfield-map-first/SKILL.md`;
- teach strict surface roles;
- require AGENTS.md -> docs -> Beads pointer -> llm-tldr verification;
- update skill metadata for activation;
- regenerate AGENTS baseline.

Acceptance:

- skill appears in generated baseline;
- skill does not contain repo-specific architecture facts;
- skill references `dx-repo-memory-check` and `dx-regen-docs`;
- skill explains source-code final truth and repo-doc map role.

### Phase 6: Canonical Repo Pilot

Beads:

- `bd-s6yjk.1`: Pilot: apply repo memory contract to canonical repos.

Tasks:

- apply the contract to `agent-skills`;
- apply the contract to `affordabot` with complex docs index;
- apply the contract to `prime-radiant-ai`, repairing stale root docs or linking
  to current docs;
- apply the contract to `llm-common` or document a smaller exception;
- create/update Beads KV pointers for each repo.

Acceptance:

- each canonical repo has required docs or explicit exception;
- AGENTS.md routes to those docs;
- `dx-repo-memory-check` passes in each repo;
- Beads KV pointers exist and point to real docs.

### Phase 7: dx-review Gate

Beads:

- `bd-s6yjk.4`: Review gate: dx-review checks repo memory compliance.

Tasks:

- update `templates/dx-review/architecture-review.md`;
- add optional `templates/dx-review/contracts/repo-memory-compliance.md`;
- include review criteria:
  - map docs present;
  - stale-if paths adequate;
  - Beads pointers not duplicative;
  - no repo truth stored in skills;
  - maintenance burden reasonable;
  - founder cognitive load minimized.

Acceptance:

- architecture review template asks repo-memory questions;
- reviewers can issue findings against missing or stale maps;
- review-only contracts remain intact.

### Phase 8: CI and dx-check Integration

Beads:

- New child: `bd-s6yjk.8` - `Wire: dx-check and GitHub Actions`.

Tasks:

- call `dx-repo-memory-check` from `dx-check` when repo opts in;
- add optional GitHub Actions workflow or reusable check;
- define waiver syntax;
- document failure examples.

Acceptance:

- local `dx-check` warns/fails appropriately;
- CI check blocks missing map updates in opted-in repos;
- waiver is explicit and grep-able.

## Proposed Beads Structure

Existing:

- `bd-s6yjk` - Canonical repo memory and brownfield map contract.
- `bd-s6yjk.3` - Spec: repo-owned brownfield memory contract.
- `bd-s6yjk.2` - Skill: brownfield map first workflow.
- `bd-s6yjk.1` - Pilot: apply repo memory contract to canonical repos.
- `bd-s6yjk.4` - Review gate: dx-review checks repo memory compliance.

Add:

- `bd-s6yjk.5` - Impl: dx-repo-memory-check.
- `bd-s6yjk.6` - Impl: dx-regen-docs mechanical inventories.
- `bd-s6yjk.7` - Impl: epyc12 repo-memory audit loop.
- `bd-s6yjk.8` - Wire: dx-check and GitHub Actions.

Dependencies:

```text
bd-s6yjk.3 -> bd-s6yjk.5
bd-s6yjk.5 -> bd-s6yjk.6
bd-s6yjk.5 -> bd-s6yjk.7
bd-s6yjk.5 -> bd-s6yjk.2
bd-s6yjk.2 -> bd-s6yjk.1
bd-s6yjk.5 -> bd-s6yjk.8
bd-s6yjk.2 -> bd-s6yjk.4
bd-s6yjk.4 -> architecture lock
```

Parallelism after Phase 2:

- `bd-s6yjk.6` and `bd-s6yjk.7` can proceed in parallel.
- `bd-s6yjk.2` can proceed once checker behavior is defined.
- Canonical repo pilots should wait for checker and skill, then split by repo.

Dispatch note:

Subtask IDs are historical, not execution order. Follow dependency edges and the
phase order in this spec, not numeric suffixes. For example, `bd-s6yjk.1` is the
canonical repo pilot and should not start first despite having suffix `.1`.

## Validation Gates

### Functional

- `dx-repo-memory-check` catches stale docs for changed paths.
- `dx-repo-memory-check` validates required frontmatter.
- `dx-regen-docs` is deterministic.
- `dx-repo-memory-audit` can run read-only on epyc12.

### Integration

- `dx-check` invokes the checker in opted-in repos.
- GitHub Actions can run the checker without secrets.
- dx-review architecture template includes repo-memory compliance.
- Beads KV pointers are valid and short.

### Quality

- External dx-review agrees the plan minimizes overlapping surfaces or returns
  actionable changes.
- At least one canonical repo pilot proves the loop end to end.
- A simulated stale path change fails the checker and is resolved by doc update.

### Founder Cognitive Load

- No manual daily monitoring required.
- One command/report gives status.
- Stale docs become Beads work items automatically.
- Agents have deterministic first-stop routing.

## Risks and Mitigations

### Risk: Docs Still Go Stale

Mitigation:

- `stale_if_paths`;
- `last_verified_commit`;
- local/CI checks;
- epyc12 audit loop;
- dx-review gate.

### Risk: Too Many Docs

Mitigation:

- minimum required docs per repo;
- complex docs only for complex repos;
- AGENTS.md links only to the index;
- generated content lives under `generated/`.

### Risk: Too Much CI Friction

Mitigation:

- repo opt-in first;
- warning mode before blocking mode;
- explicit waiver format;
- deterministic no-network checker.

### Risk: Beads Memory Search Pollution

Mitigation:

- reserve bare `memory` label for closed durable memory records;
- active work uses `repo-memory` or `memory-system`;
- checker/audit can flag open issues with bare `memory`.

### Risk: Agents Ignore Docs

Mitigation:

- `brownfield-map-first` skill;
- AGENTS.md required routing;
- dx-review findings;
- `dx-check` stale detection.

## Rollout Strategy

Default posture: `ALL_IN_NOW` for `agent-skills` contract and one canonical repo
pilot. This removes recurring rediscovery tax.

Suggested order:

1. Land spec after dx-review.
2. Implement checker.
3. Pilot in `agent-skills` and `affordabot`.
4. Add skill and regenerate baseline.
5. Add epyc12 audit.
6. Expand to `prime-radiant-ai` and `llm-common`.
7. Move CI from warning to blocking once false positives are acceptable.

## dx-review Focus

Reviewers should evaluate:

1. Is the initial problem framed correctly and grounded in the audit?
2. Is the landscape of Beads/bdx, llm-tldr, Serena, AGENTS.md, skills,
   context-area skills, and Markdown docs accurately represented?
3. Does the proposed solution keep truth in one place and use other surfaces as
   pointers/workflow/verification?
4. Does the design minimize overlapping memory surfaces?
5. Does the design minimize agent confusion with a deterministic first-stop
   workflow?
6. Does the design minimize maintenance cost and complexity?
7. Does the design minimize founder cognitive load?
8. Are the epyc12 audit loop, dx-check, CI, and dx-regen-docs boundaries clean?
9. Are any acceptance criteria too weak to prevent another Affordabot-style
   rediscovery failure?

## Recommended First Executable Task

Start with `bd-s6yjk.3`:

- run dx-review on this spec;
- patch the spec based on review findings;
- update Beads with final child task descriptions and dependencies.

Do not start implementation until dx-review confirms the boundary is coherent or
its findings are explicitly incorporated.
