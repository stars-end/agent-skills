# ContextPlus DX Governance

**ContextPlus** is the persistent memory backend for our agent workspaces. It acts as a graph of knowledge gathered from previous tasks, allowing agents to share insights without rewriting extensive context files manually.

## Core Governance Rule
**The ContextPlus memory graph MUST serve exclusively as persistent context passed via `.dx-context`. It DOES NOT replace or override the canonical dispatch and orchestration pathways.**

### Architectural Boundaries
1. **Context via `.dx-context`**: ContextPlus data (memories, links, graphs) must be resolved and passed to agents as static context or available through MCP during a task. It lives downstream of orchestration.
2. **Execution via `dx-runner`/`dx-batch`**: All actual job dispatch, task batching, and workflow orchestration must still flow exclusively through `dx-batch` (orchestration) and `dx-runner` (execution lane).

ContextPlus is a **state store**, not a **director**. It provides the "what" (history, references, semantic code maps), while `dx-runner` provides the "how" (throughput lanes, fallback, process lifecycle). An agent reads from ContextPlus, but is orchestrated by DX tools.
