# Gas City Mapping

Use this reference when deciding whether to run a goal-seeking loop through
Gas City instead of Codex-native orchestration.

## What Gas City Already Provides

Gas City includes primitives that overlap with autoresearch-style loops:

- `gc converge`: bounded iterative refinement loops
- convergence formulas
- manual, condition, and hybrid gates
- per-iteration artifact directories
- max iteration limits
- retry, iterate, terminate, approve, and stop controls
- Beads-backed loop state
- formula dispatch and agent routing

Do not rebuild those primitives in a product repo.

## What The Skill Still Supplies

Gas City does not define domain quality. The skill still supplies:

- fixed eval cases;
- scalar score;
- hard gates;
- keep/discard rule;
- failure taxonomy;
- mutation boundaries;
- final acceptance criteria.

## Selection Guidance

Use Codex-native loops when the work needs tight in-session product judgment or
must stay within Codex subagents.

Use Gas City convergence when the loop must outlive the session, run through
external LLM providers, or maintain durable iteration state outside Codex.
