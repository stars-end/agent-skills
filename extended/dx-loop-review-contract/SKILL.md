---
name: dx-loop-review-contract
description: |
  Deterministic review contract for dx-loop reviewer runs. Enforces findings-first
  review style, concrete verdicts, and machine-actionable end states for baton
  automation.
tags: [workflow, review, dx-loop, baton]
allowed-tools:
  - Read
  - Bash
---

# dx-loop Review Contract

Use this contract when acting as the reviewer in a `dx-loop` implement -> review baton.

## Goals

- Give the orchestrator a verdict it can act on without interpretation
- Keep review findings concrete and high-signal
- Prevent "looks good" approvals that ignore overclaims or missing validation

## Review Style

1. Findings first
2. Focus on correctness, regressions, overclaims, contract drift, and missing validation
3. Cite files or evidence when possible
4. Keep summaries brief

## Required Verdict

End with exactly one of:

- `APPROVED: <reason>`
- `REVISION_REQUIRED: <findings summary>`
- `BLOCKED: <critical issue>`

## Decision Rules

- `APPROVED` only when the task scope is met and the claimed validation is sufficient
- `REVISION_REQUIRED` when the code is fixable within the same task wave
- `BLOCKED` when the task cannot safely proceed without external decision or missing dependency

## Minimum Checks

- implementation matches the Beads task
- PR/handoff claims match the actual diff
- validation matches the claimed outcome
- remaining risks are surfaced, not hidden
