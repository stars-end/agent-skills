# Gas City Mapping

Gas City can be a better fit when the work is explicitly about external multi-agent optimization rather than Codex repo orchestration.

Use Gas City when:

- the optimizer agents should run outside Codex;
- candidates are mostly prompts, policies, source-selection settings, or scoring parameters;
- a fixed scalar scoring function already exists;
- git integration and code review are secondary.

Keep the Codex-native loop when:

- repo code, tests, migrations, or UI are the main mutation target;
- the orchestrator must inspect diffs and preserve worktree/Feature-Key discipline;
- the campaign needs Beads, PR, and DX validation gates;
- the eval still needs human-readable post-mortems between cycles.

## Decision Tree

```text
Is the mutation mainly repo code or runtime wiring?
  yes -> Codex-native goal-seeking loop
  no  -> continue

Is the candidate space parameterized and safe to explore automatically?
  yes -> Gas City or Autoresearch-style harness
  no  -> Codex-native loop until parameters are defined

Does every candidate have a deterministic scalar score and hard-gate result?
  yes -> external harness is viable
  no  -> Codex-native loop, then promote once eval stabilizes
```

## Handoff Shape

Create a handoff artifact with:

- objective;
- fixed eval cases and version/hash;
- score function;
- hard gate function;
- candidate schema;
- allowed parameter ranges;
- budget;
- artifact storage path;
- accept/reject rule;
- final acceptance gate.

The handoff should not include secrets. It should reference safe secret-loading wrappers or runtime configuration by name.
