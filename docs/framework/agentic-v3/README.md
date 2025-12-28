# Agent-Native Infrastructure (V3 DX)

This framework ensures high-velocity, high-rigor engineering for a team of 4 LLM agents and 1 human engineer across multiple repositories and VMs.

## The 3-Layer Defense

1.  **Layer 1: Cognitive Scaffolding (Skills):** Standardized tools (`start`, `sync`, `finish`) that automate process hygiene.
2.  **Layer 2: Immutable Physics (Hooks):** Global git hooks (`pre-push`, `post-merge`) that enforce build integrity.
3.  **Layer 3: Autonomous Oversight (Agents):** High-volume LLM loops (`Night Watchman`, `Janitor`) that hunt for regressions and toil.

## Component Map

| Component | Target | Model |
| :--- | :--- | :--- |
| **State Recovery** | Local DX | Shell |
| **Lockfile Guardian** | PR Safety | GLM-4.7 |
| **Env Resolver** | Portability | GLM-4.7 |
| **Night Watchman** | Master QA | 4.6v + 4.7 |
| **Contract Validator** | Dependency Safety | Jules |

