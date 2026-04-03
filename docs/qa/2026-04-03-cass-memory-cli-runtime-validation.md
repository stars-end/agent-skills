# CASS Memory Pilot CLI/Runtime Validation (bd-cg23)

- Date (UTC): 2026-04-03
- Scope: direct CLI/runtime validation for pilot starter package from PR 464
- Source PR: https://github.com/stars-end/agent-skills/pull/464
- CLASS: dx_loop_control_plane
- NOT_A_PRODUCT_BUG: true

## Summary Verdict

Recommendation: **adjust** before broad pilot usage.

Why:
1. `cm` runtime is healthy and can store/retrieve pilot-style entries.
2. Pilot templates and runbook framing are directionally good.
3. Starter package currently documents outdated command examples (`remember`/`recall`/`list`) that do not exist in installed `cm` v0.2.3.
4. Default retrieval settings can look like false negatives until threshold/query tuning is applied.

## Exact Commands and Observed Behavior

### 1) Runtime health

```bash
cm --version
cm quickstart --json
```

Observed:
- `cm --version` -> `0.2.3`
- `cm quickstart --json` -> `success: true`

Status: **PASS**

### 2) Command-surface compatibility check

```bash
cm --help
cm add --help
cm similar --help
```

Observed:
- Installed command set uses `add`, `similar`, `playbook list`, `context`.
- `remember` command is not present.

Status: **PASS** (for runtime introspection), with a documentation mismatch finding.

### 3) Pilot-style memory creation

Test ID used: `20260403T155220Z`

```bash
cm add "BD-CG23 20260403T155220Z mcp context eof triage playbook: if MCP context EOF but search passes, verify via contained CLI, restart per-project daemon, retry context, restart client only if transport stays stale." --json
cm add "BD-CG23 20260403T155220Z fleet audit red host drift playbook: confirm audit timestamp, run host remediation hint, rerun daily audit, compare same host/check id before escalation." --json
cm add "BD-CG23 20260403T155220Z deploy-truth check: verify service identity sha and timestamp before product signoff, treat unknown commit identity as infra truth gap." --json
cm playbook list --json
```

Observed:
- All three entries were created successfully.
- Returned bullet IDs:
  - `b-mnj30uyy-o0m2jo`
  - `b-mnj30v1f-sstnky`
  - `b-mnj30v40-d3m2ar`

Status: **PASS**

### 4) Retrieval quality (exact and near-miss)

Commands:

```bash
cm similar "BD-CG23 20260403T155220Z mcp context eof" --json
cm similar "codex mcp parser empty response daemon restart" --json
cm similar "BD-CG23 mcp context eof triage" --threshold 0.1 --limit 10 --json
cm context "handle mcp context eof daemon restart" --json
```

Observed:
- Default `cm similar` queries returned no results for the first two checks.
- Lowering threshold to `0.1` produced the expected hit.
- `cm context` returned the expected relevant bullet without threshold tuning.

Status: **PARTIAL PASS**

Interpretation:
- Retrieval is usable, but default `similar` behavior can look empty/noisy unless operator tunes threshold or prefers `cm context`.

### 5) Privacy negative test (process-level; no sensitive store)

Command:

```bash
CAND='Candidate memory with secret sk-live-12345 and cookie sessionid=abc'
if echo "$CAND" | rg -qi '(sk-|sessionid=|token|cookie|password|secret)'; then
  echo 'PRIVACY_GATE=BLOCKED_NOT_STORED'
fi
```

Observed:
- `PRIVACY_GATE=BLOCKED_NOT_STORED`
- No sensitive candidate was written via `cm add`.

Status: **PASS** (process-level gate)

## Starter Package Assessment

Files assessed:
- `docs/specs/2026-04-03-cass-memory-cross-vm-dx-pilot.md`
- `docs/runbook/cass-memory-pilot-quickstart.md`
- `docs/runbook/cass-memory-pilot-example-entries.md`
- `templates/cass-memory-pilot-entry-template.md`
- `templates/cass-memory-pilot-reuse-log-template.csv`
- `extended/cass-memory/SKILL.md`

Assessment:
1. Pilot contract boundaries and redaction policy are clear.
2. Example entries are practical and scoped correctly.
3. Template is sufficient for sanitization + evidence links.
4. Quickstart command examples currently assume old CLI aliases (`remember`/`recall`/`list`) and should be updated to current `cm` commands.

## Pass/Fail by Test Area

1. Runtime health: **PASS**
2. Basic create/list flow: **PASS**
3. Exact retrieval (out-of-box): **PARTIAL PASS**
4. Near-miss retrieval (out-of-box): **PARTIAL PASS**
5. Privacy negative process test: **PASS**
6. Operator clarity from docs/templates: **PARTIAL PASS** (command mismatch)

## Retrieval Quality / Noise Assessment

- Default `similar` retrieval in this run had high false-negative behavior.
- `cm context` provided better practical recall for incident-style queries.
- Suggested operator guidance for pilot usage:
  1. use `cm context "<incident/task>" --json` as default retrieval path
  2. use `cm similar` with explicit `--threshold` tuning when needed

## Privacy/Redaction Observations

- Pilot redaction rules are strong in docs.
- Process-level gating can prevent accidental sensitive writes.
- No sensitive content was stored during this validation.

## Open Risks

1. Documentation-command drift can block adoption or cause false failure reports.
2. Retrieval defaults may appear empty to operators unless guidance is explicit.
3. Pilot metrics can be skewed if command misuse is interpreted as model/tool failure.

## Recommended Next Actions

1. Update quickstart/skill examples to current command surface:
   - `cm add` / `cm playbook list` / `cm context` / `cm similar`
2. Add one short note on `cm similar` threshold tuning in quickstart.
3. Keep privacy gate pattern in operator flow for manual entries.

## Validation Artifacts

- `/tmp/bd-cg23-cm-validation.log`
- `/tmp/bd-cg23-cm-validation-v2.log`
- `/tmp/bd-cg23-cm-validation-v3.log`
