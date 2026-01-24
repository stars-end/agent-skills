# Tech-Lead Review: Auto-Checkpoint Feature

## Context

We've completed a POC for an **auto-checkpoint feature** that uses GLM-4.5 FLASH (cheap/fast model) to generate intelligent commit messages for dirty repos before automated sync runs.

**Problem solved:** Current `ru sync` cron skips dirty repos, blocking updates across VMs when agents have uncommitted work.

## POC Results ✅

**Test output from `~/agent-skills/poc/auto-checkpoint/test_working_final.py`:**

```
Test 1/4
  Input: docs/REPO_SYNC_STRATEGY.md | 1 +
  ✅ [AUTO] update repo sync strategy doc (36 chars)

Test 2/4
  Input: src/auth.py | 5 +2
  ✅ [AUTO] update auth logic (24 chars)

Test 3/4
  Input: README.md | 10 +++
  ✅ [AUTO] update readme (20 chars)

Test 4/4
  Input: pkg/new_feature | 100 +
  ✅ [AUTO] add new feature package (30 chars)
```

**Key findings:**
1. GLM-4.5 FLASH works for simple commit message generation
2. Must disable thinking mode: `extra_body={"thinking": {"type": "disabled"}}`
3. Otherwise returns `reasoning_content` instead of `content` (known llm-common behavior, we're working around it)

## Implementation Overview

**Architecture:**
```
Every 4 hours (agent-skills):
  :05  auto-checkpoint.sh ~/agent-skills  # Commit dirty work
  :10  ru sync agent-skills               # Now can proceed

Daily 12:00 UTC (all repos):
  12:00  auto-checkpoint.sh --all-repos
  12:05  ru sync --all
```

**Components:**
1. `auto-checkpoint.sh` - Bash script for dirty repo detection and checkpoint flow
2. `generate_commit.py` - Python script using llm-common + GLM-4.5 FLASH
3. Cron integration - 5-minute stagger before existing `ru sync`
4. Fallback behavior - `[AUTO] checkpoint` if LLM fails

**Full implementation plan:** `~/agent-skills/docs/AUTO_CHECKPOINT_IMPLEMENTATION.md`

## Questions for Review

### 1. Architecture & Integration

**Q:** Does the complementary design (auto-checkpoint → ru sync) align with the existing repo sync strategy in `docs/REPO_SYNC_STRATEGY.md`?

**Context:** Auto-checkpoint runs 5 minutes before `ru sync` to clean dirty repos so sync can proceed. This is non-blocking (fallback to static message) and preserves work.

### 2. GLM-4.5 Workaround

**Q:** We're working around the llm-common `reasoning_content` issue by disabling thinking. Is this acceptable, or should we PR a fix to `~/llm-common`?

**Code:**
```python
response = await client.chat_completion(
    messages=[{"role": "user", "content": prompt}],
    model=GLMModels.FLASH,
    extra_body={"thinking": {"type": "disabled"}},  # Workaround
)
```

**Alternative:** Modify `ZaiClient.chat_completion()` to fallback to `reasoning_content` if `content` is empty.

### 3. Failure Handling

**Q:** What's the acceptable threshold for LLM failures before alerting?

**Current behavior:** Silent fallback to `[AUTO] checkpoint`
**Options:**
- A) Always silent (current)
- B) Alert after N consecutive failures (configurable)
- C) Log warning only, no alert

### 4. Beads Integration

**Q:** If `bd sync` fails, should we:
- A) Proceed with checkpoint anyway (work may be lost on conflict)
- B) Abort checkpoint (safer but blocks sync)

**Current:** Log warning, proceed with checkpoint.

### 5. Scope & Rollout

**Q:** Should `--all-repos`:
- A) Scan `~/` for all git repos (dynamic discovery)
- B) Use a hardcoded list (affordabot, prime-radiant-ai, llm-common, agent-skills)
- C) Read from a config file

**Current:** Hardcoded list in implementation plan.

### 6. Commit Message Format

**Q:** Is `[AUTO]` prefix sufficient, or do you prefer:
- A) `[AUTO]` - current
- B) `[CHECKPOINT]` - more explicit
- C) No prefix - cleaner git log

### 7. Conflict Resolution

**Q:** If `ru sync` creates merge conflicts after checkpoint, should we:
- A) Let them conflict (manual resolution)
- B) Auto-resolve with `git checkout --theirs`
- C) Alert via Slack/notification

**Current:** Let them conflict (manual resolution).

## Decision Request

Please review and confirm:

| Decision | Option | Notes |
|----------|--------|-------|
| llm-common fix | Workaround (current) vs PR | See Q2 |
| Failure threshold | Silent vs Alert | See Q3 |
| Beads failure handling | Proceed vs Abort | See Q4 |
| Repo scope | Hardcoded vs Dynamic | See Q5 |
| Commit prefix | `[AUTO]` vs Other | See Q6 |
| Conflict resolution | Manual vs Auto | See Q7 |

## Next Steps (After Approval)

1. Create Beads epic for tracking
2. Implement `auto-checkpoint.sh`
3. Implement `generate_commit.py`
4. Add integration tests
5. Deploy to epyc6 (test environment)
6. Monitor logs for 24 hours
7. Rollout to homedesktop-wsl and macmini

## References

- **Implementation plan:** `~/agent-skills/docs/AUTO_SYNC_IMPLEMENTATION.md`
- **POC code:** `~/agent-skills/poc/auto-checkpoint/test_working_final.py`
- **Existing sync strategy:** `~/agent-skills/docs/REPO_SYNC_STRATEGY.md`
- **dirty-repo-bootstrap:** `~/agent-skills/dirty-repo-bootstrap/snapshot.sh` (reference for checkpoint flow)
- **llm-common:** `~/llm-common/llm_common/providers/zai_client.py` (GLM models)

---

**Prepared by:** Claude (cc-glm)
**Date:** 2026-01-24
**Status:** Awaiting tech-lead review
