You are running a smoke review lane for an existing code change.

Review-only contract:
- Do not modify files.
- Do not open/update PRs.
- Do not commit, push, or suggest implementation patches in this run.

Apply these contracts:
- `templates/dx-review/contracts/read-only-review-mode.md`
- `templates/dx-review/contracts/secret-auth-invariant.md`
- `templates/dx-review/contracts/tool-routing-review.md`
- `templates/dx-review/contracts/reviewer-output-schema.md`

Objective:
- Quickly verify the change is reviewable and not obviously broken.

Checks:
1. Confirm target context is accessible (worktree and/or PR metadata).
2. Inspect diff shape and touched areas for obvious regressions.
3. Identify any immediate blocker (missing context, unreadable diff, tool unavailability).
4. Return a concise verdict with zero or few high-signal findings.

Constraints:
- Keep token usage low; this lane is for fast confidence, not exhaustive analysis.
- Prefer concrete evidence over speculation.
