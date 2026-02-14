# Handoff Template

## Investigation Document Template

```markdown
# [Topic] Analysis

**Date:** YYYY-MM-DD
**Investigator:** <Agent/Name>
**Beads Epic:** bd-xxxx
**Status:** Ready for review | In Progress | Blocked

---

## Executive Summary

<1-2 paragraphs summarizing the issue and resolution>

---

## 1. Root Cause Analysis

### 1.1 The Incident

<What happened, when, impact>

### 1.2 Timeline

| Time (UTC) | Event | Evidence |
|------------|-------|----------|
| ... | ... | ... |

### 1.3 Root Cause

<The actual root cause with confidence level>

### 1.4 Contributing Factors

<Additional factors that contributed>

---

## 2. Evidence

### 2.1 Database Evidence

```sql
-- Query used
SELECT ... FROM ...
```

| Column | Value |
|--------|-------|
| ... | ... |

### 2.2 Code Evidence

**File:** `path/to/file.py` (lines X-Y)

```python
# Relevant code
```

**Analysis:** <What this code shows>

### 2.3 Log Evidence

```
Log output showing the issue
```

---

## 3. Fix Plan

### 3.1 Beads Epic

```
○ bd-xxxx [EPIC] Title [Priority]
  ↳ bd-xxxx.1: Subtask 1 [Priority]
  ↳ bd-xxxx.2: Subtask 2 [Priority]
```

### 3.2 Implementation Details

| Subtask | Files to Modify | Changes |
|---------|-----------------|---------|
| bd-xxxx.1 | file1.py | Add heartbeat recording |
| bd-xxxx.2 | file2.py | Add missing run detection |

### 3.3 Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

---

## 4. Recommendations

### Immediate Actions
1. Action 1
2. Action 2

### Process Improvements
1. Improvement 1

---

## Appendix

### Commands Used

```bash
# Command 1
command --flag

# Command 2
another-command
```

### References

- [Link 1](url)
- [Link 2](url)
```

## Handoff Summary Template

```markdown
# Tech Lead Review: [Topic]

**Handoff Date:** YYYY-MM-DD
**Beads Epic:** bd-xxxx
**Full Doc:** docs/investigations/YYYY-MM-DD-<topic>-analysis.md

---

## Quick Summary

- **What happened:** <1 sentence>
- **Root cause:** <1 sentence with confidence>
- **Fix plan:** Epic bd-xxxx with N subtasks

---

## Evidence Summary

| Evidence | Source | Finding |
|----------|--------|---------|
| <Item 1> | <Source 1> | <Finding 1> |
| <Item 2> | <Source 2> | <Finding 2> |

---

## Beads Structure

```
○ bd-xxxx [EPIC] Title [P1]
  ↳ bd-xxxx.1: Subtask 1 [P1]
  ↳ bd-xxxx.2: Subtask 2 [P1]
  ↳ bd-xxxx.3: Subtask 3 [P2]
```

---

## Files to Modify

| File | Subtask | Changes |
|------|---------|---------|
| path/to/file | bd-xxxx.1 | Description |

---

## Decisions Required

1. **Decision 1:** <Context and options>
2. **Decision 2:** <Context and options>

---

## How to View

- **Beads:** `bd import ~/bd/.beads/issues.jsonl` then `bd show bd-xxxx`
- **Full Doc:** `docs/investigations/YYYY-MM-DD-<topic>-analysis.md`
- **GitHub:** https://github.com/org/repo/blob/.../docs/investigations/...
```

## Self-Contained Prompt Template

```
## Tech Lead Review: [Topic]

**GitHub:** https://github.com/org/repo/blob/BRANCH/docs/investigations/...
**Beads Epic:** bd-xxxx
**Investigation:** docs/investigations/YYYY-MM-DD-<topic>-analysis.md

### Summary
- **What happened:** <1-2 sentences>
- **Root cause:** <1-2 sentences with key evidence>
- **Fix plan:** bd-xxxx with N subtasks (P1/P2 breakdown)

### Key Evidence
1. <Evidence 1 - include source>
2. <Evidence 2 - include source>
3. <Evidence 3 - include source>

### Beads Structure
○ bd-xxxx [EPIC] Title [P1]
  ↳ bd-xxxx.1: Subtask 1 [P1]
  ↳ bd-xxxx.2: Subtask 2 [P1]

### Decisions Needed
1. <Decision 1>
2. <Decision 2>

### How to View
- **Beads:** Import from `~/bd/.beads/issues.jsonl`
- **Docs:** See `docs/investigations/` in repo
- **PR:** <link if applicable>
```
