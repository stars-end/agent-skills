# Tech Lead Review: gskill Deployment

**PR**: https://github.com/stars-end/agent-skills/pull/229
**Epic**: bd-3umt
**Status**: Updated with fixes

---

## Tech Lead Feedback (Received)

### P0 Issues (Fixed)

| Issue | Fix Applied |
|-------|-------------|
| opencode CLI flags wrong (`-p` → positional, `--output-format` → `--format`, `--workdir` → `--dir`) | Fixed in bd-3umt.2, bd-3umt.3, bd-3umt.8 |
| GEPA reflection_lm in wrong place | Fixed in bd-3umt.4: moved to `GEPAConfig(reflection=ReflectionConfig(reflection_lm=...))` |
| Evaluator lambda signature incompatible | Fixed in bd-3umt.3, bd-3umt.4: evaluator now `(candidate, example=...)` |

### P1 Issues (Fixed)

| Issue | Fix Applied |
|-------|-------------|
| GEPAResult fields don't exist | Fixed in bd-3umt.4: use `best_candidate`, `val_aggregate_scores[best_idx]`, `candidates` |
| Reflection template placeholders wrong | Fixed in bd-3umt.5: now uses `<curr_param>`, `<side_info>` |
| Dict tasks vs dataclass mismatch | Fixed in bd-3umt.8: tasks are dicts, use `task.get('id')` |

### P2 Issues (Fixed)

| Issue | Fix Applied |
|-------|-------------|
| SWE-smith function doesn't exist | Fixed in bd-3umt.1: use `MAP_EXT_TO_MODIFIERS` |
| AGENTS.md manual edit will be overwritten | Fixed in bd-3umt.11: use `make publish-baseline` |

---

## Open Questions - ANSWERED

| Question | Decision |
|----------|----------|
| Reflection model: glm-5 or Claude? | **Start with glm-5** for simplicity, keep Claude as optional A/B |
| Initial scope: single repo or both? | **Start with prime-radiant-ai only** |
| Skill storage location? | **.gskill/** for generated, promote selected to **.claude/skills/** for runtime |
| Evolution budget? | **Start with max_metric_calls=100**, scale to 300 once stable |

---

## Summary

This plan deploys the gskill pipeline (SWE-smith + GEPA) to automatically learn repository-specific skills for coding agents. The approach follows the methodology from the GEPA paper which demonstrated:
- 55% → 82% resolve rate improvement on Jinja
- 24% → 93% on Bleve
- Skills learned on smaller models transfer to Claude Code

## What This Enables

1. **Automated skill learning** - No manual skill authoring for repo-specific patterns
2. **Measurable improvement** - Pass rate tracking before/after skills
3. **Transfer learning** - Skills learned on one repo may help on similar repos
4. **Continuous improvement** - Re-run as codebase evolves

## Architecture Decision

```
SWE-smith (task generation, no LLM)
    ↓
    300 synthetic tasks
    ↓
GEPA optimize_anything (evolution loop)
    ├── Agent: opencode + glm-5
    ├── Reflector: opencode + glm-5 (Claude optional)
    └── Output: evolved SKILL.md
```

**Key design choice**: Using opencode as both agent and reflector means NO external API keys required.

## Task Structure

| Phase | Tasks | Parallel? | Est. Time |
|-------|-------|-----------|-----------|
| T1: Core Infrastructure | 3 | Yes (T1.1, T1.2) | 4h |
| T2: GEPA Integration | 2 | T2.5 only | 3h |
| T3: Repo Adapters | 2 | Yes | 2h |
| T4: Orchestration | 2 | Sequential | 3h |
| T5: Validation | 2 | Yes | 2h |

**Total**: ~14h implementation time

## Dependencies

External (already cloned):
- `~/SWE-smith` - Task generation
- `~/gepa` - Skill optimization

Internal (to be created):
- `extended/gskill/` - New skill directory

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| SWE-smith requires Linux | Medium | High | Run on epyc6, or build macOS shim |
| GEPA loop is slow | High | Medium | Start with max_metric_calls=100 |
| Learned skills are low quality | Medium | Medium | Validate with `gskill evaluate` |
| opencode timeout issues | Medium | Low | Configurable timeout in adapter |

## Acceptance Criteria

### Core Requirements
- [ ] Can generate 100+ tasks for prime-radiant-ai
- [ ] Can run skill evolution loop (even if slow)
- [ ] Produced skills improve agent pass rate by measurable amount
- [ ] Skills are stored in repo-specific location
- [ ] Process is reproducible and documented

### Critical Planning-Level Requirements (bd-3umt Round 3)

These requirements ensure the plan uses REAL failing instances, not synthetic descriptions:

| Task | Requirement | Why Critical |
|------|-------------|--------------|
| bd-3umt.1 | Tasks admitted ONLY when mutation causes verified failing tests | No "instructional-only" tasks |
| bd-3umt.1 | No `echo 'No test file'` fallback | Every task must have real test |
| bd-3umt.1 | Apply `modifier.modify(entity)`, extract code from `BugRewrite.rewrite` | Real bug injection |
| bd-3umt.1 | Use `RepoProfile.extract_entities_from_file()` (NOT nonexistent swesmith.utils) | Correct SWE-smith API |
| bd-3umt.1 | Patch uses `a/` and `b/` prefixes for `patch -p1` compatibility | Patch applies correctly |
| bd-3umt.1 | Task includes `mutated_code` field (NOT `original_code`) | Evaluator has mutation data |
| bd-3umt.3 | Load/apply mutation BEFORE agent run | Evaluate on mutated state |
| bd-3umt.3 | Use `mutated_code` field, fail fast if missing | No original-code fallback |
| bd-3umt.3 | Repo/task isolation with tempfile | Prevent cross-contamination |
| bd-3umt.3 | Patch application uses `-p1` for `a/` `b/` prefixed paths | Matches generator format |
| bd-3umt.4 | Use `current_candidate` key for string candidates | Correct GEPA API |
| bd-3umt.4 | Wire reflection template via `ReflectionConfig(reflection_prompt_template=...)` | Custom reflection enabled |
| bd-3umt.4 | Dependencies include bd-3umt.2, .3, .5 (metadata matches description) | Correct scheduling |
| bd-3umt.5 | Template uses `<curr_param>`, `<side_info>` placeholders | GEPA compatibility |
| bd-3umt.6/.7 | Exclude patterns use fnmatch (glob), NOT substring | Patterns actually work |
| bd-3umt.10 | Tests set patterns BEFORE discover_targets() OR use defaults | No test/generator mismatch |

### Validation Gates

1. **Task Generator Validation**: Each task must fail its test when mutation is applied
2. **Evaluator Validation**: Score reflects recovery from failing mutated instances
3. **Exclude Validation**: `*/migrations/*` actually excludes migration files
4. **Reflection Template Validation**: Template loaded and passed to GEPA config

## Review Checklist

- [x] Architecture is sound (SWE-smith → GEPA → SKILL.md)
- [x] Task breakdown is complete and properly sequenced
- [x] Dependencies are correct (no circular deps)
- [x] Implementation specs are actionable
- [x] Risks are identified with mitigations
- [x] Open questions are addressed
- [x] P0/P1/P2 issues fixed

## Recommendation

**Approved for implementation** with the following configuration:
- Reflection model: glm-5 (Claude optional)
- Initial scope: prime-radiant-ai only
- Budget: max_metric_calls=100 (scale to 300 after validation)
- Storage: .gskill/ → promote to .claude/skills/

---

## Reviewer Notes

**Approved**: [x] Yes [ ] No [ ] With changes

**Comments**:
```
All P0/P1/P2 issues have been addressed. The plan is ready for implementation.
Start with prime-radiant-ai, budget=100, and validate the pipeline before scaling.
```

**Reviewer**: Tech Lead
**Date**: 2026-02-21
