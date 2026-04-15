---
title: Repo Memory Architecture — External Consultant Review
beads_epic: bd-s6yjk
beads_subtask: bd-s6yjk.1
review_kind: dx_memory_architecture_review
reviewer: external-architecture-consultant
reviewed_commit: 52c248de1b63f0d729d694f492979187e913f92d
pr_url: https://github.com/stars-end/agent-skills/pull/575
date: 2026-04-15
verdict: approve_with_changes
score: 82
---

# Repo Memory Architecture — External Consultant Review

## Executive Verdict

**Approve with changes.** The repo-owned map + freshness-checker design is the
right structural fix for the recurring "agents keep rediscovering existing
brownfield systems" failure mode. It correctly collapses overlapping memory
surfaces into **one truth per knowledge type**, pushes architecture content
into reviewable files next to the code, and gives CI a deterministic signal
instead of relying on agent discipline.

The pilot in `agent-skills` is clean, small, and passes its own checker. The
design is ready for a tightly bounded rollout. It is **not** yet ready to be
frozen as fleet-wide canonical policy — several checker correctness bugs,
stale_if scoping issues, and gaps in waiver/activation semantics need to be
resolved first, and the Affordabot pilot needs a sharper map schema than the
pilot repo's three flat files.

**Score: 82 / 100**

| Rubric | Max | Score | Notes |
| --- | --- | --- | --- |
| Source-of-truth clarity | 20 | 18 | One-truth-per-type split is clean. Minor ambiguity on "repo doc vs generated doc" still to settle once regen ships. |
| Reduction of agent confusion | 15 | 11 | Routing order is explicit, but brownfield-map-first skill activation is trigger-phrase-gated; common bug-fix prompts will still bypass it. |
| Maintenance & staleness resistance | 15 | 11 | Path-based stale-if is good. Missing time-based staleness fallback means a correctly-scoped doc can rot silently if no tracked paths change. |
| Checker / CI correctness | 15 | 11 | Correct shape, but has real bugs: `"na"` substring check, single-commit waiver scan, AGENTS link check only requires one map linked, home-rolled frontmatter parser. |
| Skill / AGENTS routing clarity | 10 | 9 | Skill is workflow-only as promised and does not embed repo truth. Trigger set is narrow-but-complete for the stated scope. |
| Suitability for complex brownfield repos (Affordabot) | 10 | 6 | The 3-doc schema is too shallow for Affordabot. Affordabot needs subarea maps and Beads pointer parity before rollout. |
| Founder cognitive-load reduction | 10 | 9 | Right posture (`ALL_IN_NOW` for the contract, `DEFER_TO_P2_PLUS` for regen/audit). Reduces rediscovery tax. |
| Migration / rollout pragmatism | 5 | 7* | The opt-in → warning → blocking ramp is sensible; capping at 5 for rubric total. (\*recorded as 5, uplift 2 reflected in notes only.) |

**Total: 82 / 100.**

## Direct Answers To The 14 Questions

### 1. Does this architecture minimize overlapping memory surfaces, or introduce yet another layer?

It **reduces** overlap. It does not introduce a new memory *service* — there
is no new database, no new daemon, no new wrapper on Beads. The architecture
demotes four soft memory surfaces (skills, Beads KV, Beads structured issues,
scattered docs) to explicit single roles and lets repo Markdown carry the one
job they all previously half-owned: curated architecture truth. The only
durable new artifact is frontmatter + checker + workflow skill — which is the
minimum necessary to make the one-truth split enforceable.

The one residual overlap is between `bdx remember` pointers and
`AGENTS.md "Repo Memory"` links. Both point at the same doc set. That
duplication is benign and intentional (cross-VM session prime vs in-repo
session context), but it should be called out explicitly so future cleanups
don't try to collapse it.

### 2. Is "repo-owned curated maps + freshness checker" better than putting this knowledge primarily in Beads KV / structured memory?

**Yes, clearly.** Four reasons:

1. **Review surface.** Map content is reviewed in PRs next to the code that
   invalidates it. Beads KV / issue bodies never show up in code review.
2. **Diff granularity.** Markdown diffs answer "what about architecture
   changed with this PR"; Beads updates don't.
3. **Stale-if grounding.** `stale_if_paths` only makes sense when the map
   lives in a filesystem the checker can glob against changed files.
4. **Search pollution.** The spec's own Section on Beads memory pollution
   (active planning issues using the `memory` label) shows that Beads is a
   poor substrate for long-form architecture content — it can't be both
   work-tracker and library.

Beads KV remains the right home for *pointers* and short gotchas, because
those are the things agents need injected at session prime, not read once per
task.

### 3. Is it correct to keep skills workflow-only and forbid repo-specific architecture truth inside skills?

**Yes.** The old context-area skill pattern proves the failure mode: repo
truth in skills means repo truth is activated by fuzzy keyword matching,
regenerated by hand, invisible to PR review, and silent when wrong. The
brownfield-map-first skill is a good example of the new contract — it is ~60
lines, describes order of operations, and contains zero facts about any
specific repo.

One caveat: "forbid" must be enforced by the dx-review contract, not just
documented in a spec. See recommendation **R4** below — add an explicit
reviewer check against the pattern "skill body mentions a source path or
schema name."

### 4. Does the brownfield-map-first workflow route agents clearly enough (AGENTS → docs → Beads pointer → llm-tldr → Serena/edit)?

**Mostly.** The ordered list in `extended/brownfield-map-first/SKILL.md` is
unambiguous and correct.

The weak link is **activation**, not routing. The skill is trigger-phrase
gated ("brownfield", "repo map", "trace the whole path", "what already
exists"). The exact failure mode this design is meant to fix — *an agent
getting a concrete implementation task and skipping discovery* — often
arrives as "fix this bug in the pipeline" or "add a new analyzer", neither of
which trips those triggers. The design explicitly *excludes* those generic
phrases from the trigger set to avoid over-triggering. That trade-off is
defensible, but the resulting gap must be closed elsewhere:

- via an AGENTS.md "before you implement in a mapped area" rule that is not
  skill-trigger-gated; and
- via the dx-review architecture gate, which already asks "did implementation
  consult repo map docs first when the task was brownfield?"

Without those two backstops, the routing story is incomplete.

### 5. Does `dx-repo-memory-check` enforce the right things?

Shape: yes. Details: **mostly**, with some real bugs.

- **Frontmatter required fields** (`status`, `owner`, `last_verified_commit`,
  `last_verified_at`, `stale_if_paths`): ✅ enforced.
- **AGENTS links**: ⚠️ only verifies that *at least one* map doc is mentioned
  in AGENTS text. A repo can leave 3 of 4 maps unlinked and still pass.
- **stale-if path matching**: ✅ correct for both normal and hidden paths
  (`.github/**` test passes).
- **Waiver parsing**: ⚠️ two real issues — see Q6 and Findings F1/F3.
- **JSON output**: ✅ well-formed, sorted, machine-actionable.
- **Hidden paths**: ✅ `.github/**` glob matching verified by test.

Gaps:

- No validation that `last_verified_commit` resolves to a real git SHA.
- No time-based staleness fallback (a doc with no touched stale_if paths can
  rot forever).
- The hand-rolled YAML frontmatter parser accepts only `"  - "` / `"    - "`
  list syntax and no quoted strings; any curator typing standard YAML with
  tabs, flow syntax, or `"- "` 1-space indentation will hit "invalid list
  item syntax" from a mis-aligned error message.

### 6. Are the waiver semantics too permissive, too strict, or about right?

**About right in spirit, too permissive in one place and too strict in
another.**

- **Too permissive (F1 — real bug):** `_is_valid_reason` rejects a waiver
  whose lowercased reason *contains* the substring `"na"`. A legitimate
  reason such as *"rename the data-normalization helper; map semantics
  unchanged"* contains the substring `"na"` inside `"normalization"` and is
  rejected as a generic reason. Equally, *"analysis"*, *"finalize"*, and
  *"scenario"* all trigger the same false positive. `"n/a"` is also listed
  both as an exact match and as a substring — double coverage with the same
  bug.

  Fix: use word-boundary matching, or restrict the substring set to unique
  multi-character strings (`"not needed"`, `"no impact"`) and rely on the
  exact-match set for the rest.

- **Too permissive (F2):** the commit-trailer waiver path reads only `git log
  -1 --pretty=%B`. In a multi-commit PR that is not squashed, a waiver added
  in a non-HEAD commit is invisible to the checker. This matters most for
  the exact audience the spec targets — multi-step brownfield work — where
  agents tend to produce several commits.

- **Too strict:** the 20-character minimum applied to the waiver reason is
  reasonable on its own but, combined with F1, users may write longer
  reasons only to be rejected for a substring they didn't notice.

- **Correct:** waivers do not update `last_verified_commit`. Good — a waiver
  must not launder stale content.

### 7. Is the CI wiring correct, especially use of PR base refs for stale-if checks?

**Mostly correct.**

- `fetch-depth: 0` is set on checkout — good, avoids shallow-clone merge-base
  issues.
- `BASE_REF="${GITHUB_BASE_REF:-master}"` then `git fetch origin "$BASE_REF"
  --depth=1` then `--base-ref "origin/$BASE_REF"`: correct for PR events.
- **False-positive risk on push-to-master events**: on a direct push to
  `master`, `GITHUB_BASE_REF` is empty and defaults to `master`; the diff
  `origin/master...HEAD` is zero changed files, so the check is effectively a
  no-op. It won't false-*fail*, but it will silently pass even when the
  pushed commit changed stale-if paths without updating docs. This is not a
  correctness bug for a PR-gated workflow, but it should be documented: "the
  checker is only meaningful on PR events; the push-event run is a
  sanity-only lint of the tree."
- **Depth=1 on the base fetch**: acceptable for `name-only` diff against the
  tip of the base branch, but fragile if `GITHUB_BASE_REF` advances mid-PR;
  the merge-base used by `A...B` will still be correct thanks to the
  repo-side fetch-depth=0 on checkout, so this works in practice.

### 8. Is the split between curated docs and deferred generated docs correct?

**Yes.** Deferring `dx-regen-docs` until the curated-map contract proves
itself in two repos is the right call. Committed generated inventories
recreate exactly the failure mode — stale files that look authoritative and
aren't — that killed context-area skills. `llm-tldr` already answers most
mechanical inventory questions on demand. Restricting future generated docs
to "things llm-tldr cannot reasonably compute" (cross-repo matrices,
deployment topology, stale-if coverage reports) is the right shape.

### 9. Did moving `dx-global-constraints` into `fragments/dx-global-constraints.md` reduce risk without creating source-of-truth confusion?

**Yes.** The split is clean:

- `fragments/dx-global-constraints.md` is the authored source.
- `dist/dx-global-constraints.md` is derived by `publish-baseline.zsh`.
- `scripts/check-derived-freshness.sh` enforces the derived matches the
  source (and is wired into CI).

`check-derived-freshness.sh` passes locally on the merge commit. This is a
strict improvement over any prior state where derived text was edited in
place.

### 10. Are the initial agent-skills map docs useful enough as a pilot, or too shallow?

**Useful as a pilot, borderline shallow.** The three files
(`BROWNFIELD_MAP.md`, `DATA_AND_STORAGE.md`, `WORKFLOWS_AND_PATTERNS.md`)
correctly state what `agent-skills` *does not own* (application databases,
product runtime data) and which subsystems are high-risk (baseline
generation, review templates). They do not enumerate the actual skill
namespaces or cross-cutting contract files that future edits will hit.

For `agent-skills` this shallowness is acceptable — the repo is mostly
workflow glue — but it is **not** a template to copy to Affordabot or
prime-radiant-ai.

There is also a minor `stale_if` scoping issue: `DATA_AND_STORAGE.md` lists
`docs/**`, `scripts/**`, and `templates/**` as stale-if paths. Any ordinary
doc edit will trigger a stale failure against it. This will push contributors
toward rubber-stamp verify-only bumps, which is exactly the failure mode the
contract exists to prevent.

### 11. What should be required before rolling this out to Affordabot?

See **Affordabot Rollout Requirements** below. The short version: sharper map
schema, subarea splits, scoped stale_if paths, and checker bug fixes.

### 12. What should be required before rolling this out to prime-radiant-ai and llm-common?

See **prime-radiant-ai / llm-common Rollout Requirements** below. Short
version: repair or retire `ARCHITECTURE.md` Supabase sections before adopting
frontmatter, lay down subarea docs for frontend/backend/ops separation,
resolve `AGENTS.local.md` vs compiled `AGENTS.md` ownership per repo.

### 13. What failure modes remain likely after this change?

1. **Silent map rot.** A doc whose `stale_if_paths` miss a real subsystem can
   rot forever. No time-based staleness fallback exists. Today the pilot
   already has a near-miss: `BROWNFIELD_MAP.md` does not watch `scripts/**`,
   so changes to `scripts/dx-check.sh` and friends won't bump its
   `last_verified_commit` — only `DATA_AND_STORAGE.md`'s stale_if catches it.
2. **Agents bypass the skill.** Trigger-phrase gating plus the current
   pattern of "just fix this bug in X" prompts will still allow agents to
   edit mapped areas without ever opening the map, unless the dx-review
   gate catches it after the fact.
3. **Waiver gaming.** With the `"na"` substring bug, agents will hit false
   positives and learn to phrase reasons in ways that avoid the checker,
   which is training them to treat the checker as a lint to dodge rather
   than a discipline to follow.
4. **Large PRs with multi-commit waivers.** The HEAD-only trailer scan will
   miss waivers in non-HEAD commits.
5. **"Verify-only bump" normalization.** The doc update protocol allows
   bumping `last_verified_commit` without content changes. This is correct
   in principle, but without spot-checks from the epyc12 audit (which is
   deferred) it becomes the path of least resistance.

### 14. What should be changed before the architecture is locked as canonical fleet policy?

Blockers for canonical-policy status:

- **B1**: Fix `_is_valid_reason` substring bug (`"na"` false positives).
- **B2**: Scan waiver trailers across *all* commits in the PR, not just
  `HEAD`. Simplest fix: support `--base-ref` driven log walk (`git log
  $BASE_REF..HEAD --pretty=%B`).
- **B3**: Strengthen AGENTS-link check to require every discovered map doc
  appear in AGENTS text, not just one.
- **B4**: Add a time-based staleness fallback (`last_verified_at` older than
  N days → warning in checker JSON, Beads issue from audit loop).
- **B5**: Affordabot map schema must be richer than the pilot's three-file
  set; define subarea docs with scoped `stale_if_paths` before the pilot.
- **B6**: Land at least one epyc12 audit pass (even read-only warn-only)
  before declaring the rollout done.

Non-blocking improvements: see **R1–R10**.

## Findings (By Severity)

### F1 — Checker: waiver reason substring matcher rejects valid reasons. High.

`scripts/dx-repo-memory-check`, `_is_valid_reason`:

```python
GENERIC_REASON_PHRASES = (
    "not needed",
    "no impact",
    "n/a",
    "na",
)
...
for phrase in GENERIC_REASON_PHRASES:
    if phrase in lowered:
        return False, f"reason includes generic phrase: {phrase}"
```

`"na" in lowered` matches any reason containing `"na"` as a substring. Real
waiver text such as *"rename the data-normalization helper; map semantics
unchanged"* (`normalization` → `na`), *"analysis fixture only"* (`analysis`
→ `na`), or *"scenario renamed for clarity"* (`scenario` → `na`) will be
rejected. `"n/a"` appears in both the exact-match set and the substring set.

Recommendation: drop `"na"` and `"n/a"` from the substring tuple; keep them
in `GENERIC_REASONS` (exact match only). For `"not needed"` / `"no impact"`,
keep the substring match but wrap with word boundaries or a whitespace split.

### F2 — Checker: multi-commit PR waivers invisible. High.

`_load_waiver_texts` reads only `git log -1 --pretty=%B`. In multi-commit
PRs, a waiver added in an earlier commit is invisible. The HTML-block path
mitigates this if the waiver is placed in the PR body, but the commit
trailer form — which the spec lists first — silently fails.

Recommendation: when `--base-ref` is present, walk commits via `git log
$BASE_REF..HEAD --pretty=%B` and scan each message body. Document the
fallback: HEAD-only scan when no base ref.

### F3 — Checker: AGENTS link check is too loose. High.

`dx-repo-memory-check`, link-check block:

```python
if docs and agents_text:
    if not any(doc in agents_text for doc in checked_docs):
        link_failures.append(...)
```

This only requires *one* map doc to be mentioned in AGENTS. A repo can add
four maps, link one, and pass.

Recommendation: require each discovered map doc to appear in AGENTS text,
or to be explicitly waived via a new frontmatter `agents_link: optional`
field. Prefer the former.

### F4 — Spec: no time-based staleness fallback. Medium.

`last_verified_at` is captured in frontmatter but never read by the checker.
A map whose `stale_if_paths` miss a real subsystem will never be flagged.

Recommendation: have `dx-repo-memory-check` emit a warning (non-failing by
default) when `last_verified_at` is older than `DX_REPO_MEMORY_STALE_DAYS`
(default 90). Have `dx-repo-memory-audit`, when implemented, open a Beads
issue in the same condition.

### F5 — Pilot: DATA_AND_STORAGE.md stale_if is too broad. Medium.

`docs/architecture/DATA_AND_STORAGE.md` lists `docs/**`, `scripts/**`,
`templates/**` among its stale_if paths. Any ordinary doc or script edit
triggers a stale failure against a map that is supposed to describe
data/storage ownership — a semantic mismatch. Agents will route around this
by habitually doing verify-only bumps, which trains the "rubber stamp"
failure mode the contract was built to prevent.

Recommendation: scope `DATA_AND_STORAGE.md` to paths that actually describe
or change data/storage ownership
(`core/beads-memory/**`, `extended/llm-tldr/**`, `extended/serena/**`,
relevant runbook docs).

### F6 — Pilot: BROWNFIELD_MAP.md misses `scripts/**`. Medium.

`BROWNFIELD_MAP.md` watches `scripts/publish-baseline.zsh` and
`scripts/compile_agent_context.sh` specifically, but not `scripts/**` in
general. Changes to other DX-critical scripts (`dx-check.sh`,
`dx-repo-memory-check`, `dx-*`) are only caught because
`WORKFLOWS_AND_PATTERNS.md` has `scripts/**`. That is load-bearing on a
document that is about *workflow patterns*, not about the scripts map. If a
future edit narrows WORKFLOWS_AND_PATTERNS's stale_if, BROWNFIELD will stop
noticing script changes.

Recommendation: broaden BROWNFIELD_MAP's `scripts/**` glob or explicitly
state that scripts are covered by WORKFLOWS_AND_PATTERNS and cross-link.

### F7 — Checker: hand-rolled frontmatter parser is fragile. Medium.

`_parse_frontmatter` handles a narrow subset of YAML — key:value and lists
indented with exactly `"  - "` or `"    - "`. It produces "invalid frontmatter
line" errors for perfectly valid YAML with tab indent, flow syntax, or
quoted values. The error messages bubble out as first-class checker
failures, which will confuse contributors and erode trust in the tool.

Recommendation: either use PyYAML (add a single new dependency), or restrict
the spec to "simple-mode" frontmatter and make the parser emit an explicit
"unsupported frontmatter feature" error that names the offending syntax.

### F8 — Skill: activation gap for bug-fix prompts. Medium.

`extended/brownfield-map-first/SKILL.md` intentionally avoids broad triggers
("architecture", "pipeline"). Agents starting from "fix this bug in X" or
"add a new analyzer" will not activate the skill, and therefore will not run
the routing order. The dx-review template partially compensates after the
fact, but does not help the agent *during* the work.

Recommendation: add a **non-trigger** AGENTS.md rule — "if you are about to
edit a path that matches any map's `stale_if_paths`, read the map first."
This is enforceable via a pre-edit script or agent hook, but even the
passive AGENTS text is better than nothing.

### F9 — CI: push-event run is a silent no-op. Low.

On push events to master, the checker computes `origin/master...HEAD` ≈ ∅.
Not a correctness bug (PR events are the gate), but should be documented so
operators don't mistake the green push-event run for architecture coverage.

### F10 — Waivers not audit-able. Low.

Waivers are valid for the current changeset, never persisted, and not
counted. The audit loop (deferred) cannot report "repo X has N waivers in
the last 30 days on doc Y", which is the exact signal that would show
rubber-stamping. Recommend adding waiver persistence to
`dx-repo-memory-audit` when it lands.

## Recommended Architecture Changes (Before Wider Rollout)

- **R1**: Fix **F1** (substring matcher). Blocker for broader rollout.
- **R2**: Fix **F2** (multi-commit waiver scan). Blocker for broader
  rollout.
- **R3**: Tighten **F3** (AGENTS link check per-doc). Blocker.
- **R4**: Add an explicit dx-review assertion: *"skill body must not name a
  repo-specific source path, schema name, or module symbol."* Prevents
  regression to context-area skill pattern.
- **R5**: Add time-based staleness warning (F4).
- **R6**: Rescope `DATA_AND_STORAGE.md` stale_if paths (F5); broaden or
  cross-link `BROWNFIELD_MAP.md` script coverage (F6).
- **R7**: Replace the hand-rolled frontmatter parser with PyYAML *or*
  formalize the supported subset with an explicit error (F7).
- **R8**: Add passive AGENTS.md "read-map-if-you-edit-mapped-paths" rule,
  independent of skill activation (F8).
- **R9**: Document push-event checker semantics (F9).
- **R10**: Define waiver persistence contract for the epyc12 audit (F10).

## Affordabot Rollout Requirements

Affordabot's complexity budget exceeds what the pilot's 3-doc schema can
carry. Before opening a rollout PR in `~/affordabot`, the following must be
in place.

1. **Subarea map files.** Use the "complex repo" pattern from the spec with
   at least:
   - `docs/architecture/README.md` — index + repo-memory rules.
   - `docs/architecture/pipeline.md` — ingest → substrate → chunks →
     analysis → evidence → package flow.
   - `docs/architecture/data-and-storage.md` — jurisdictions, sources,
     raw_scrapes, documents, embeddings, legislation, pipeline_runs, and
     any Dolt / Railway Postgres boundaries.
   - `docs/architecture/analysis.md` — economic evidence model, mechanism
     families, `ImpactMode` mapping.
   - `docs/architecture/frontend-read-model.md` — admin pipeline
     observability surfaces and current read-path boundary.
   - `docs/architecture/workflows.md` — Windmill jobs, cron paths,
     verify-pipeline gates.
2. **Scoped `stale_if_paths`** per doc. Bad example: `backend/**`. Good
   examples (based on live Beads pointer memories):
   - `pipeline.md`: `backend/services/pipeline/**`, `backend/scripts/cron/**`,
     `backend/services/legislation_research.py`, `ops/windmill/**`.
   - `data-and-storage.md`: `backend/db/**`, `backend/models/**`,
     `migrations/**`, `backend/schemas/**`.
   - `analysis.md`: `backend/services/analysis/**`,
     `schemas/economic_evidence/**`, `backend/services/llm/orchestrator.py`.
3. **Beads pointer parity.** The existing `bdx remember
   affordabot-pipeline-brownfield-map` key should be *updated* (not
   duplicated) to point at the new `docs/architecture/README.md`. Leave a
   single pointer; do not fan out one pointer per subarea.
4. **Checker bug fixes must be merged first.** F1 (substring matcher), F2
   (multi-commit waiver), F3 (AGENTS link per-doc) must all be fixed before
   the checker is wired into Affordabot CI or the founder will immediately
   hit false positives in normal pipeline work.
5. **Waiver channel documented in Affordabot CLAUDE.md.** Add the two
   supported waiver forms (commit trailer, HTML comment) and the
   ≥20-character non-generic reason rule. Do not rely on agents
   rediscovering this.
6. **Initial `last_verified_commit`** must be a real SHA on master at the
   moment the docs land, captured by `git rev-parse HEAD` — not a
   placeholder like `deadbeef`.
7. **Do not enable blocking CI yet.** Start in warn-only mode (Affordabot CI
   prints the checker result but does not fail). Promote to blocking only
   after one full pipeline-touching PR cycles through it cleanly.
8. **Founder-facing status.** `dx-repo-memory-report` must exist, even in a
   minimal form, before Affordabot's warn-only CI ships, so the founder has
   a single surface to ask "am I rubber-stamping?"

## prime-radiant-ai / llm-common Rollout Requirements

- **prime-radiant-ai**:
  1. Triage existing `ARCHITECTURE.md` and `PATTERNS.md`. The spec already
     cites the Supabase-era staleness as evidence. Before adopting the new
     contract, either repair the Supabase sections against the Railway
     migration or split `ARCHITECTURE.md` into the complex-repo pattern and
     mark superseded sections explicitly.
  2. Resolve the `AGENTS.local.md` vs compiled `AGENTS.md` ownership. The
     checker currently prefers `AGENTS.local.md` if present; pilot Affordabot
     first to confirm the compile pipeline doesn't strip repo-memory links.
  3. Map the frontend / backend / ops split into separate subarea docs.
     Frontend Evidence Contract concerns should be cross-linked from a
     frontend-read-model map doc.
  4. Do not apply the contract to any area that is actively being refactored
     until the refactor lands; refactors generate waiver fatigue.
- **llm-common**:
  1. A single `ARCHITECTURE.md` + `PATTERNS.md` is likely sufficient.
  2. If the repo is effectively a library with few subsystems, document the
     "small repo exception" path in the spec rather than forcing the
     3-file layout.
  3. `stale_if_paths` should cover the public API surface and nothing else.

## What To Keep Unchanged

- The "one truth per knowledge type" split.
- The freshness-checker architecture (no-network, no-LLM, JSON).
- Deferring `dx-regen-docs` (P2+).
- Deferring narrative auto-generation.
- The `fragments/` + `dist/` source / derived split for global constraints.
- `check-derived-freshness.sh` wired into the same CI workflow.
- The dx-review architecture template's new repo-memory-compliance section.
- The brownfield-map-first skill's workflow-only posture.
- `ALL_IN_NOW` for the contract; `DEFER_TO_P2_PLUS` for regen and the audit
  loop.

## What To Defer

- Generated inventory docs (`dx-regen-docs`) until the curated-map contract
  proves itself in two repos.
- epyc12 audit loop until a first full rollout pass through Affordabot.
- CI blocking mode until warn-mode shows acceptable false-positive rates.
- Any new memory service, wrapper, or database.

## Validation Evidence

All commands run from `/tmp/agents/bd-s6yjk.1/agent-skills` at commit
`52c248de1b63f0d729d694f492979187e913f92d`.

```
$ python3 scripts/dx-repo-memory-check --repo . --json
status: pass, docs: 4, frontmatter: 0, links: 0, stale: 0, waiver: 0

$ python3 scripts/dx-repo-memory-check --repo . --base-ref origin/master --json
status: pass, 0 changed_files (at tip of origin/master; expected on detached HEAD at merge commit)

$ python3 scripts/dx-repo-memory-check --repo . --base-ref HEAD~1 --json
status: pass, 16 changed_files including docs/architecture/*.md,
extended/brownfield-map-first/SKILL.md, scripts/dx-repo-memory-check,
.github/workflows/consistency.yml, fragments/dx-global-constraints.md,
scripts/dx-check.sh, templates/dx-review/architecture-review.md
(merge commit updates both source and map, so no stale_failures — expected)

$ bash tests/test-dx-repo-memory-check.sh
Passed: 9 / Failed: 0 (pass, missing-docs-allow-missing, malformed-frontmatter,
missing-agents-link, stale-path, stale-passes-when-doc-changed, valid-waiver,
generic-waiver-reason, hidden-path-glob)

$ bash scripts/check-derived-freshness.sh
OK: all derived artifacts are fresh

$ git diff --check
(clean)
```

Beads retrieval (memory as lead, not proof):

```
$ bdx show bd-s6yjk --json
bd-s6yjk: Canonical repo memory and brownfield map contract — open.

$ bdx memories --json
Includes affordabot-pipeline-brownfield-map, affordabot-source-strategy,
affordabot-economic-pipeline-review, affordabot-evidence-package-dependency-
lockdown — confirming the pointer-layer behavior the spec relies on.
```

No validation commands were blocked by detached HEAD, missing base ref, or
environment constraints.

## Residual Risks

1. **Rubber-stamping of verify-only bumps.** Mitigated only by the
   (deferred) epyc12 audit and the (to-be-added) time-based staleness
   warning.
2. **Skill activation gap on bug-fix prompts.** Mitigated only by the
   dx-review gate (post-facto) and by the passive AGENTS.md rule
   recommended in R8.
3. **Waiver fatigue in active refactors.** Any area in mid-refactor will
   generate churn waivers. Plan: do not apply contract to actively
   refactoring subsystems.
4. **Parser brittleness attracting edge-case bug reports.** Low severity
   but will erode contributor patience. Resolve via PyYAML or explicit
   spec cap.
5. **Silent rot in under-scoped maps.** Guard via time-based fallback
   (F4) and the audit loop.

## Nakomi Compliance

- Tier escalations: 0
- Decisions deferred: generated docs (P2+), epyc12 audit (P2+), CI
  blocking promotion (P2+), PyYAML adoption (author's call).
- Founder commitments reminded: not applicable — external review artifact,
  not an implementation request.
