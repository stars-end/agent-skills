# llm-tldr Semantic Auto-Bootstrap

## Summary

Add wrapper-level semantic auto-bootstrap in `agent-skills` so the contained `llm-tldr` surface makes first-call semantic search usable without manual `semantic index` prep.

This wave stays entirely in our wrapper / runtime / docs layer. It does not fork or patch upstream `llm-tldr`.

## Problem

Current fleet policy says `llm-tldr` is the canonical first tool for semantic discovery. In practice, semantic search fails on a fresh host x repo-path combination until a semantic index has been built for that exact project path.

That creates a real DX blocker:
- `tree`, `search`, `context`, and structural tools may work
- `semantic` fails on first use with `Semantic index not found ... Run build_semantic_index first.`
- agents fall back to shell/file reads or broader runtime inspection even when semantic discovery is the intended first route

This is especially brittle because semantic readiness is path-scoped. Worktrees and nested repo paths can behave like fresh projects even on otherwise healthy hosts.

## Goals

1. Make `~/agent-skills/scripts/tldr-contained.sh semantic search ...` succeed on first use for an unindexed project path.
2. Preserve the existing containment contract so `.tldr/` and `.tldrignore` never appear inside project trees.
3. Keep the upstream package untouched.
4. Make MCP-driven semantic calls benefit from the same bootstrap behavior.
5. Keep failure messaging precise when bootstrap itself fails.

## Non-Goals

1. Forking or patching upstream `llm-tldr`.
2. Reworking structural cache warmup.
3. Redesigning the semantic model choice beyond preserving upstream defaults and caller overrides.
4. Guaranteeing zero-latency first semantic call. Initial bootstrap may be slower; the goal is usability, not hiding that cost.

## Active Contract

After this change:
- semantic search through the contained CLI or contained MCP path should automatically build the semantic index for the target project path when missing
- later semantic searches should reuse the cached index
- explicit `semantic index` remains supported for operators who want to prebuild or choose a different model intentionally
- docs should describe `semantic index` as an optional prewarm optimization, not a required first-call step for the contained surface

## Design

### Local Root Cause

Upstream `llm-tldr` treats semantic indexing as a separate prerequisite:
- docs imply `warm` or first use should be enough
- actual `semantic search` hard-fails when semantic index artifacts are absent

We already own a local runtime boundary:
- `scripts/tldr-contained.sh`
- `scripts/tldr-contained-cli.py`
- `scripts/tldr_contained_runtime.py`
- `scripts/tldr-mcp-contained.py`

That boundary is the right place to bridge the mismatch.

### Chosen Approach

Implement lazy semantic bootstrap in the contained runtime.

#### CLI path

When the contained CLI sees a semantic search request:
1. resolve the target project path from CLI args
2. determine whether the semantic index exists for that project path under contained state storage
3. if missing, run the semantic index build inside the same contained runtime
4. retry semantic search automatically

This should preserve:
- caller-provided project/path
- caller-provided model if present
- containment patching for any `.tldr` path access during index build

#### MCP path

When the contained MCP server receives a semantic search command:
1. inspect the daemon command payload before forwarding search
2. if the semantic index is missing for that project path, build it once through the contained runtime
3. then forward the original search command

This keeps IDE agents from needing separate operational steps.

### Preferred Implementation Shape

Keep the fix narrow and explicit:
- add helper(s) in `tldr_contained_runtime.py` for:
  - detecting semantic search intent
  - resolving the target project path and model
  - checking whether index artifacts exist in the contained state bucket
  - invoking contained semantic index build
- keep `tldr-contained.sh` and `tldr-mcp-contained.sh` as thin entrypoints
- avoid duplicating upstream semantic logic beyond the small bootstrap gate

### Failure Contract

If bootstrap fails, return a clear local error that distinguishes:
- missing semantic index detected
- attempted auto-bootstrap
- bootstrap failure reason

This is better than the current ambiguous first-use failure because it preserves the real cause and the local mitigation attempt.

## Execution Phases

### Phase 1: Reproduce and Pin the Bootstrap Gap
- prove semantic search fails on an unindexed project path through the contained wrapper
- capture the exact contained-state location for the semantic index

### Phase 2: Implement Wrapper Auto-Bootstrap
- add lazy bootstrap logic for contained CLI semantic search
- extend contained MCP search path to use the same bootstrap behavior

### Phase 3: Tighten Docs and Validation
- update `extended/llm-tldr/SKILL.md`
- update fleet/runtime contract docs if wording still says semantic indexing is always manual
- add or update a verification path that proves first-call semantic success without manual indexing

## Beads Structure

- `BEADS_EPIC`: `bd-7su7` — Make llm-tldr semantic first-call usable
- `BEADS_CHILDREN`:
  - `bd-7su7.1` — Add wrapper-level semantic auto-bootstrap
  - `bd-7su7.2` — File upstream llm-tldr semantic readiness bug
- `BLOCKING_EDGES`:
  - `bd-7su7.2` blocks on `bd-7su7.1`

## Validation

### Required implementation proof

From a clean worktree / repo path with no prebuilt semantic index:

```bash
AGENT_SKILLS_WT=<agent-skills-worktree>
AFFORDABOT_WT=<repo-path-or-worktree>

find "$AFFORDABOT_WT" -name .tldr -o -name .tldrignore
find "$HOME/.cache/tldr-state" -path "*semantic*" | head

"$AGENT_SKILLS_WT/scripts/tldr-contained.sh" semantic search "railway db" --path "$AFFORDABOT_WT" --k 3
```

Expected result:
- semantic search succeeds without a prior manual `semantic index`
- no `.tldr` or `.tldrignore` appears in the repo tree

### Reuse proof

Run the same semantic search again and confirm it does not rebuild unnecessarily.

### MCP proof

Verify the contained MCP surface can still serve semantic search after the bootstrap logic is added.

### Cleanliness gate

```bash
cd ~/agent-skills
~/agent-skills/scripts/dx-verify-clean.sh
```

## Risks / Rollback

### Risks
- first semantic call becomes slower because indexing is now on-demand
- bad argument parsing in the wrapper could mishandle uncommon semantic CLI forms
- MCP bootstrap needs to avoid repeated or racy rebuild attempts

### Mitigations
- keep the parser narrow and focused on semantic search/index arguments only
- only bootstrap when index artifacts are absent
- preserve explicit `semantic index` for operators and tests
- document that manual pre-indexing is still useful when lower latency matters

### Rollback

If the wrapper change proves unstable, revert the bootstrap hook and keep the contained path as-is. The upstream issue should still be filed because the docs/code mismatch remains real.

## Recommended First Task

Start with `bd-7su7.1`.

Why first:
- it removes the active usability blocker in the local product surface we control
- it gives us concrete validation evidence before we file the upstream bug in `bd-7su7.2`
