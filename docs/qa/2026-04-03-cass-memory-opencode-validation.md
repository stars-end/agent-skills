# CASS Memory OpenCode Validation

CLASS: dx_loop_control_plane
NOT_A_PRODUCT_BUG: true

## Summary

This QA pass checked whether the cass-memory pilot starter package is usable by an agent through `opencode`, not just readable by a human.

Result:
- `opencode` is available and has a usable non-interactive `run` surface.
- The pilot starter package is usable today, but it is not fully turnkey.
- The main gaps are missing setup assumptions and one contract inconsistency in adjacent fleet docs.

## Validation Inputs

Pilot source of truth:
- PR 464: `https://github.com/stars-end/agent-skills/pull/464`
- Head SHA: `62d1e93d63fa9ec12a447862d2986e0a4614ca5f`

Read from the current checkout:
- `docs/specs/2026-04-03-cass-memory-cross-vm-dx-pilot.md`
- `docs/runbook/cass-memory-pilot-quickstart.md`
- `docs/runbook/cass-memory-pilot-example-entries.md`
- `templates/cass-memory-pilot-entry-template.md`
- `templates/cass-memory-pilot-reuse-log-template.csv`
- `extended/cass-memory/SKILL.md`

## Exact Commands Used

```bash
opencode --help | head -40
opencode run --help
opencode agent --help
opencode debug config
opencode debug paths
opencode models
cm --version && cm quickstart --json
cm doctor --json
opencode run --format json --model openai/gpt-5.4-mini --dir /tmp/agents/bd-aik5/agent-skills "Read docs/runbook/cass-memory-pilot-quickstart.md and docs/runbook/cass-memory-pilot-example-entries.md from the current checkout. Evaluate whether a new agent can realistically follow the quickstart tomorrow without hidden assumptions. Focus on gaps, missing steps, and whether the starter package is usable today. Return concise bullet findings only."
opencode run --format json --model openai/gpt-5.4-mini --dir /tmp/agents/bd-aik5/agent-skills "Pretend you are the agent tomorrow using the cass-memory pilot starter package. Using the quickstart and templates, outline the exact first actions you'd take to create one sanitized playbook entry and one reuse log row. Call out any assumptions you had to make."
```

## Observed Behavior

### OpenCode availability

- `opencode --help` shows the expected surfaces:
  - `run`
  - `agent`
  - `debug`
  - `models`
  - `session`
- `opencode models` includes a usable model set, including:
  - `openai/gpt-5.4-mini`
  - `openai/gpt-5.3-codex`
- `opencode debug config` shows `llm-tldr` and `serena` configured as MCP tools.
- `opencode debug paths` resolved normal local config/cache/state locations.

### Direct runtime checks

- `cm --version` returned `0.2.3`.
- `cm quickstart --json` succeeded and returned:
  - `success: true`
  - `oneCommand: cm context "<task>" --json`
  - degraded-mode guidance
  - privacy guidance
  - optional remote-history guidance
- `cm doctor --json` succeeded but reported `overallStatus: degraded`.
- The actionable fixable issue was:
  - repo-level `.cass` structure not initialized
  - suggested fix: `cm doctor --fix --no-interactive`

### OpenCode validation run

Fresh `opencode run` against the current checkout produced useful agent-like output.

Key findings from the first evaluation prompt:
- The agent could read the quickstart and example entries directly.
- It identified the starter package as partially usable, but not fully turnkey.
- It called out missing setup steps and ambiguity around prerequisites.

Key findings from the second prompt:
- The agent could outline the exact first actions for a sanitized memory entry:
  - verify `cm --version`
  - verify `cm quickstart --json`
  - open the entry template
  - fill sanitized metadata / trigger / procedure / rollback / source refs
  - run `cm remember "<sanitized one-paragraph summary>"`
  - add one reuse row to the CSV template
- It explicitly had to assume:
  - `cm` is installed
  - quickstart passes
  - there is a real DX/control-plane incident to record
  - the summary can be sanitized enough to avoid secrets/transcripts

## Usability Assessment

The starter package is agent-usable today, but only with caveats.

What works:
- The docs are structured enough for a new agent to follow.
- The example entries give concrete shapes for real memories.
- The templates are clear and easy to fill.
- OpenCode can reason over the package and produce a valid first-action plan.

What is still missing:
- A first-run checklist that explicitly says what to do if `cm doctor --json` reports degraded state.
- A clearer prerequisite note for repo-level memory initialization (`cm init --repo` or `cm doctor --fix --no-interactive`).
- A direct note on whether `jq` is required for the suggested validation commands.
- A clearer resolution of the adjacent contract mismatch:
  - one doc says `cass-memory` is pilot-only / disabled by default
  - another fleet-sync doc still describes it as enabled

## Hidden Assumptions

1. `cm` is already installed and on `PATH`.
2. The operator is comfortable interpreting `cm doctor --json` warnings.
3. The pilot is being used for DX/control-plane incidents only.
4. The agent knows the reuse row is for a real reuse event, not for initial entry creation.
5. The operator can sanitize the summary without needing a more prescriptive redaction checklist.

## Recommendation

Proceed, but adjust the starter package before calling it turnkey.

Recommended follow-up:
- Add a short first-run section to the quickstart for `cm doctor` degradation.
- Call out repo-level `.cass` initialization explicitly.
- Resolve the pilot/disabled wording conflict in adjacent fleet-sync docs.

## Validation Notes

- One earlier `opencode` session was started before the worktree had been refreshed with the pilot docs; that session reported missing files and was discarded.
- The fresh `opencode run` sessions against the current checkout did read the starter package successfully and produced usable agent guidance.

