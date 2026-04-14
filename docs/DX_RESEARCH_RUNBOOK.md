# dx-research Runbook

`dx-research` is the agent-facing wrapper for source-backed research and
decision memos. Use it when the desired output is evidence, tradeoffs, and a
next action, not implementation or code-review quorum.

## Routing

Use the smallest correct surface:

| Need | Surface |
| --- | --- |
| Independent code/design/security review | `dx-review` |
| Source-backed research or decision memo | `dx-research` |
| Provider debugging or custom dispatch | `dx-runner` |

Provider choice is not the agent interface. `gemini-research` is the primary
profile and `cc-glm-research` is the fallback profile behind `dx-research`.

## Standard Commands

Run a provider check before debugging a failed research run:

```bash
dx-research doctor --worktree /tmp/agents/bd-xxx/repo --with-fallback
```

Run bounded local research:

```bash
dx-research run \
  --beads bd-xxx \
  --worktree /tmp/agents/bd-xxx/repo \
  --topic "answer the narrow question" \
  --depth quick \
  --no-web \
  --local-only \
  --wait
```

Run deeper research:

```bash
dx-research run \
  --beads bd-xxx \
  --worktree /tmp/agents/bd-xxx/repo \
  --topic "compare option A vs option B for this decision" \
  --depth deep \
  --wait
```

Read the merged artifact first:

```bash
dx-research summarize --beads bd-xxx
sed -n '1,220p' /tmp/dx-research/bd-xxx/summary.md
```

## Artifacts

Artifacts live under `/tmp/dx-research/<beads-id>/`:

- `research.prompt`
- `summary.json`
- `summary.md`
- `sources.json`
- `claims.json`

Agents should read `summary.md` first. Raw dx-runner logs are debugging inputs,
not the normal handoff surface.

`summary.json` and the provider table in `summary.md` include the mutation count
reported by `dx-runner`. For read-only confidence, run research from a clean
worktree or verify that any reported mutations were pre-existing.

## Timeout Behavior

`dx-research run --wait` exits `124` on wrapper wait timeout. It still writes
partial summary artifacts before exiting so agents can report a useful status
without spelunking logs.

On timeout:

1. Read `/tmp/dx-research/<beads-id>/summary.md`.
2. Check whether the provider is still running with `dx-runner check --beads`.
3. Stop only the specific timed-out research job if it is no longer useful.
4. Narrow the prompt or switch to `--depth quick` before retrying.

Do not retry the same broad prompt repeatedly.

## Source Grounding

Major claims must map to `sources.json` through source ids, or be explicitly
marked as inference in `claims.json`.

Use `--no-web` when external browsing is disallowed.

Use `--local-only` when repo/local evidence is the only allowed source.

## Handoff

For human or orchestrator handoff, include:

- `summary.md` path
- effective result from `summary.json`
- provider outcomes
- source grounding status
- mutation count and whether the worktree was clean before the run
- timeout or fallback status, if any
