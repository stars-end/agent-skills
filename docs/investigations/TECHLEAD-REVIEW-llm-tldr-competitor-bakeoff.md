# TECHLEAD-REVIEW: llm-tldr Competitor Bakeoff

## Review Package

| Field | Value |
|-------|-------|
| MODE | investigation |
| PR_URL | https://github.com/stars-end/agent-skills/pull/593 |
| PR_HEAD_SHA | 63cb5f8c9b0f2284699af4d178ccc055d1102558 |
| BEADS_EPIC | bd-9n1t2 |
| BEADS_SUBTASK | bd-9n1t2.16 |
| BEADS_DEPENDENCIES | none |

## Artifacts

- **Full Memo**: `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md` (698 lines)
- **Analysis Summary**: `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md`

## Validation

| Check | Result |
|-------|--------|
| `dx-verify-clean.sh` | PASS — all canonical clones clean |
| `git fetch origin master --prune` | PASS |
| Worktree isolation | PASS — all work in `/tmp/agents/bd-9n1t2.16/agent-skills` |
| No canonical writes | PASS |
| No secrets in commit | PASS |
| Feature-Key in commit | bd-9n1t2.16 |
| Agent in PR body | opencode |

## Tool Evidence

- **Tools used**: Web search (prime_web_search_prime), web fetch (grepai docs, cocoindex-code docs, GitHub repos), GitHub API (`gh api`), source inspection of `~/llm-tldr` and `~/byterover-cli`, llm-tldr contained CLI runtime benchmarks
- **Routing exception**: llm-tldr MCP unavailable in this runtime; used contained CLI/fallback and source inspection instead

## Changed Files

- `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md` — comprehensive competitor bakeoff memo (new)
- `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md` — investigation summary (new)
- `docs/investigations/TECHLEAD-REVIEW-llm-tldr-competitor-bakeoff.md` — this review doc (new)

## Decisions Needed

1. **Confirm or revise recommendation**: DEFER_TO_P2_PLUS (narrow grepai spike) vs ALL_IN_NOW (replace now) vs CLOSE_AS_NOT_WORTH_IT (hardening patch)
2. **Authorize grepai spike**: Install grepai on one canonical VM, run 5 agent sessions as primary analysis tool
3. **Assess capability gap**: Are agents actually using `cfg`, `dfg`, `slice`, `dead`, `arch`, `diagnostics` in practice? If not, the gap is theoretical.

## Open Blockers / Risks

- grepai requires Ollama for local embeddings (new runtime dependency)
- Capability gap (CFG/DFG/slice/arch) may or may not matter in practice
- grepai has 67 open issues; maintainer velocity is high (push TODAY) but issue count is notable
- CodeGraphContext (179 issues, single maintainer) ruled out for P0 replacement

## How To Review

1. Open [PR #593](https://github.com/stars-end/agent-skills/pull/593)
2. Read `docs/architecture/2026-04-25-llm-tldr-competitor-bakeoff.md` — full scoring matrix, benchmark results, per-candidate findings
3. Read `docs/investigations/2026-04-27-llm-tldr-competitor-bakeoff-analysis.md` — compact summary
4. Verify Beads state: `bdx show bd-9n1t2.16 --json`
5. Decide: spike, replace, or harden
