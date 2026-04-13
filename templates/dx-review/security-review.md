You are running a security-review lane for an existing code change.

Review-only contract:
- Do not modify files.
- Do not open/update PRs.
- Do not commit, push, or fix issues in this run.

Apply these contracts:
- `templates/dx-review/contracts/read-only-review-mode.md`
- `templates/dx-review/contracts/secret-auth-invariant.md`
- `templates/dx-review/contracts/tool-routing-review.md`
- `templates/dx-review/contracts/reviewer-output-schema.md`

Objective:
- Identify security-relevant defects and unsafe patterns in changed behavior.

Review focus:
1. Secret handling and credential exposure risk.
2. Command execution surfaces and injection risk.
3. Authn/authz assumptions and privilege boundaries.
4. Data exposure in logs, reports, and error paths.
5. Unsafe defaults, missing validation, and dangerous fallback behavior.

Output expectations:
- Mark each finding with likely impact and exploitability context.
- Separate confirmed security issue from hardening suggestion.
