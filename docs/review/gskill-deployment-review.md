# Tech Lead Review: gskill Deployment

**PR**: (will be filled after PR creation)
**Epic**: bd-3umt
**Status**: Ready for review

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
    ├── Reflector: opencode + glm-5 (or Claude)
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
| GEPA loop is slow | High | Medium | Start with max_metric_calls=50 |
| Learned skills are low quality | Medium | Medium | Validate with `gskill evaluate` |
| opencode timeout issues | Medium | Low | Configurable timeout in adapter |

## Open Questions for Review

1. **Reflection model**: Should we use glm-5 or Claude for reflection? 
   - glm-5: No API key, consistent with agent
   - Claude: Better reasoning, requires API key

2. **Initial scope**: Start with prime-radiant-ai only, or both repos?
   - Single repo: Faster validation
   - Both repos: More data for patterns

3. **Skill storage**: Store in `.gskill/learned/` or `.claude/skills/learned/`?
   - `.gskill/`: Separate from handcrafted skills
   - `.claude/skills/`: Auto-loaded by Claude Code

4. **Evolution budget**: Default `max_metric_calls=300` or lower?
   - 300: Better results, 2-4 hour runtime
   - 100: Faster, may miss patterns

## Acceptance Criteria

- [ ] Can generate 100+ tasks for prime-radiant-ai
- [ ] Can run skill evolution loop (even if slow)
- [ ] Produced skills improve agent pass rate by measurable amount
- [ ] Skills are stored in repo-specific location
- [ ] Process is reproducible and documented

## Review Checklist

- [ ] Architecture is sound (SWE-smith → GEPA → SKILL.md)
- [ ] Task breakdown is complete and properly sequenced
- [ ] Dependencies are correct (no circular deps)
- [ ] Implementation specs are actionable
- [ ] Risks are identified with mitigations
- [ ] Open questions are addressed or deferred

## Recommendation

**Proceed with implementation** after addressing:
1. Choose reflection model (glm-5 vs Claude)
2. Confirm initial scope (single repo vs both)
3. Set max_metric_calls budget

---

## Reviewer Notes

_Leave your feedback here:_

**Approved**: [ ] Yes [ ] No [ ] With changes

**Comments**:
```
(Your review comments)
```

**Reviewer**: _______________
**Date**: _______________
