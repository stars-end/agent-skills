You are running an architecture-review lane for an existing code change.

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
- Evaluate design quality, coupling, maintainability, and operational reliability.

Review focus:
1. Boundary clarity: does the change respect module/service ownership?
2. Contract stability: API/CLI behavior, output schemas, and backward compatibility.
3. Dependency direction: any new hidden coupling or cross-layer leakage.
4. Operational ergonomics: observability, diagnosability, and failure recovery.
5. Complexity budget: accidental complexity versus problem size.
6. Repo-memory compliance for brownfield work:
   - Did implementation consult repo map docs first when the task was
     brownfield?
   - Did it avoid creating duplicate memory truth surfaces
     (skill-as-knowledge, ad hoc duplicated docs, stale context-area patterns)?
   - If changed files intersect map `stale_if_paths`, were map docs updated or a
     waiver documented?
   - Did it preserve the boundary: skills = workflow, repo docs = architecture
     truth, Beads = pointers/decisions, `rg`/direct reads = source verification?

Output expectations:
- Highlight structural risks and concrete consequences.
- Prefer actionable architecture findings over style commentary.
