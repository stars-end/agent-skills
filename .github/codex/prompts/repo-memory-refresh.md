# Repo Memory Refresh Prompt

You are refreshing repo-owned brownfield architecture maps.

## Contract

- Update only repo-memory documentation that is stale according to
  `repo-memory-report.json`, or clearly age-expired.
- Prefer small, conservative edits over broad rewrites.
- Every material claim you add must be grounded in current source files or
  current workflow files. Cite paths inline.
- Remove or mark uncertain claims when the current source no longer supports
  them.
- Do not edit source code, tests, migrations, lockfiles, env files, secrets,
  workflow files, scripts, skills, or generated baselines.
- Allowed scheduled-refresh files are:
  - `docs/architecture/**`
  - `AGENTS.md` only for repo-memory map link corrections
  - `AGENTS.local.md` only for repo-memory map link corrections
- If evidence is insufficient, leave files unchanged and explain why.
- If `repo-memory-report.json` says no refresh is needed, leave files
  unchanged.
- Do not use web search. This is a source-code documentation refresh, not an
  internet research task.
- Do not include general session reminders, founder reminders, or motivational
  text in the final response.

## Required Process

1. Read `repo-memory-report.json`.
2. Inspect only the files needed to verify stale docs and current source truth.
3. Apply the smallest documentation changes that make the map current.
4. Update `last_verified_commit` and `last_verified_at` only for docs you
   actually verified.
5. Keep the existing document style and scope.
6. If the audit failure is only an unreachable historical
   `last_verified_commit`, verify the doc against current source and then
   refresh the metadata instead of rewriting the prose.

## Final Response

Return:

- changed docs
- source paths inspected
- claims updated
- claims left uncertain
- whether any follow-up is needed
