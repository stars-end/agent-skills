# QA: Cass-Memory Repaired Package Validation via OpenCode (2026-04-03)

- BEADS: bd-de0j
- Source PR under test: https://github.com/stars-end/agent-skills/pull/464
- Source head SHA under test: 3f643876d448c2f67b41f0f7e1ae615ca889e97a
- CLASS: dx_loop_control_plane
- NOT_A_PRODUCT_BUG: true

## Scope
Validate that the repaired cass-memory pilot starter package is usable end-to-end for an agent operating through OpenCode, with direct CLI used for runtime execution proof.

## OpenCode-Centered Validation
OpenCode commands used:

```bash
opencode --help | head -40
opencode models | rg 'gpt-5.4-mini|gpt-5.3-codex'
opencode run --format json --model openai/gpt-5.4-mini --dir /tmp/agents/bd-de0j/agent-skills "Read repaired quickstart/example/template files and extract pilot command contract as JSON"
opencode run --format json --model openai/gpt-5.4-mini --dir /tmp/agents/bd-de0j/agent-skills "Read /tmp/bd-de0j-repro-.../meta.txt and commands.log; return strict QA verdict JSON"
```

What OpenCode could do:
- Parse repaired runbook/template package and produce command-ready flow.
- Evaluate captured runtime evidence and return structured recommendation with caveats.

What OpenCode could not do directly in this pass:
- It was not used as the command executor for `cm`; runtime proof was done via direct shell CLI.

## Runtime Command Evidence (Direct CLI)
Evidence folder:
- `/tmp/bd-de0j-repro-20260403T162254Z`

Commands executed:

```bash
cm --version
cm quickstart --json
cm doctor --json
cm doctor --fix --no-interactive
cm doctor --json
cm playbook add "BD-DE0J-20260403T162254Z MCP context EOF runbook: verify cm quickstart/doctor, repair with doctor --fix, store sanitized workflow summary, retrieve with context/similar" --category workflow --json
cm context "BD-DE0J-20260403T162254Z context eof" --json
cm similar "BD-DE0J-20260403T162254Z context eof" --json
cm similar "BD-DE0J-20260403T162254Z context eof" --threshold 0.1 --json
```

Key observed outcomes:
- `cm --version` -> `0.2.3`
- `cm quickstart --json` -> `success: true`
- `cm doctor --json` (before fix) -> `overallStatus: degraded`
- `cm doctor --fix --no-interactive` -> created repo `.cass` structure successfully
- `cm doctor --json` (after fix) -> still `overallStatus: degraded` due warnings (optional provider keys, sanitization pattern warning, guard not installed)
- `cm playbook add ... --json` -> success, bullet id `b-mnj447ec-w4n9p4`
- `cm context ... --json` -> retrieved the new bullet and related prior bullets
- `cm similar ... --json` (default threshold) -> no results
- `cm similar ... --threshold 0.1 --json` -> returns expected matches including `b-mnj447ec-w4n9p4`

## Template + Reuse-Log Exercise
- Created one sanitized workflow summary via `cm playbook add`.
- Simulated reuse-log row in CSV shape compatible with `templates/cass-memory-pilot-reuse-log-template.csv`.

## Remaining Friction / Gaps
1. `cm doctor` remains degraded after auto-fix; quickstart should explicitly define this as acceptable/non-blocking for pilot execution if that is intended.
2. `cm similar` default threshold can miss obvious near matches; runbook guidance should include threshold tuning (e.g., `--threshold 0.1`) for low-recall queries.
3. Starter template in this PR state still says `One-Paragraph Summary For cm remember`; this is legacy wording vs current `cm playbook add` flow.

## Turnkey Assessment
Recommendation: **go-with-caveats**

Reasoning:
- End-to-end core path works (preflight, fix, add, context retrieval, similar retrieval with tuning).
- It is usable tomorrow for DX/control-plane pilot usage.
- Operator-facing caveats must be explicit to avoid false-fail interpretation from degraded doctor status and default similar recall behavior.

## Final QA Verdict
- Pilot starter package is functionally usable now.
- It is not fully frictionless without caveat handling in docs.
- This is a DX/control-plane tooling quality finding, not a product defect.
