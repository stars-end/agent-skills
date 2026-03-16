# Addendum: EPYC12 Load Analysis for Centralized Embeddings

The proposal to host the centralized Ollama instance (`nomic-embed-text`) on `epyc12` needs to be evaluated against its existing workload and hardware profile.

## Hardware Profile
- **Host:** `epyc12`
- **CPU:** 12-core AMD EPYC
- **RAM:** 32GB
- **GPU:** None (CPU-only inference)

## Existing Workload
- 4x GitHub Actions Runners (can spike CPU/RAM during concurrent builds/tests).
- 2-3x active `claude-code` / `cc-glm` instances (node processes + file watching overhead).
- Fleet Sync and DX orchestration jobs.

## The Risk Profile of CPU-only Embeddings
Running `nomic-embed-text` (a 137M parameter model) via Ollama on a CPU-only host is structurally different from running a chat model, but it is **not free**. 

When multiple agents are running concurrently, the operational reality of `context-plus` means:
1. **Initial Indexing Spike:** When an agent opens a new project (or a heavily modified worktree), `context-plus` will attempt to embed hundreds of files at once. On a CPU, Ollama will aggressively saturate available cores to compute these vectors. 
2. **Resource Contention:** If a GitHub runner is compiling a frontend build (`pnpm build`) *while* two agents trigger a codebase re-index, all 12 cores will be pegged at 100%. This will lead to:
   - Runner timeouts or flaky tests.
   - Claude Code feeling sluggish or timing out on MCP calls.
   - High memory pressure (Ollama + Node.js + Webpack/Vite).
3. **RAM Footprint:** While `nomic-embed-text` is small (~275MB in RAM), Ollama's memory management and context window buffers (especially with an 8k window) will consume 1-2GB of RAM during active embedding batches. Given 32GB total and 4 active runners, RAM is less of a concern than CPU saturation.

## Why the Initial Recommendation Was Optimistic
The initial recommendation stated it "won't blow upepyc12" because it assumed steady-state incremental indexing (e.g., changing 1 file triggers 1 embedding request taking ~100ms). It did not adequately account for the "thundering herd" problem of multiple worktrees booting up simultaneously while CI runners are active.

## Revised Recommendation: The "Tethered Local" Approach

Given the heavy existing utilization of `epyc12`, relying on it as a centralized CPU-only embedding server for the entire fleet is **high risk for CPU starvation**.

Instead of a centralized architecture, we should adopt a **Tethered Local Architecture** for embeddings:

1. **Local-First Execution:** `context-plus` and Ollama should run locally on the host where the agent is executing (e.g., `macmini` runs its own Ollama, `homedesktop-wsl` runs its own). 
2. **Why this is better:** 
   - `macmini` (M-series Apple Silicon) is vastly superior for local embeddings due to unified memory and neural engine acceleration. Indexing will take seconds instead of minutes.
   - It distributes the CPU load. A local agent doing local file edits will use local compute for semantic mapping, preventing `epyc12` from becoming a bottleneck for the entire fleet.
3. **EPYC12's Role:** `epyc12` should only run `nomic-embed-text` for the agents *executing directly on epyc12*. It should NOT serve remote requests from the `macmini` or WSL hosts. 
4. **Throttle the Indexer:** When configuring `context-plus` on `epyc12`, we must explicitly restrict Ollama's CPU usage to prevent it from starving the GitHub runners:
   - Set `OLLAMA_NUM_PARALLEL=1` to prevent concurrent batch saturation.
   - Set `CONTEXTPLUS_EMBED_NUM_THREAD=4` (restrict to 4 cores out of 12).

## Conclusion
Do not centralize embeddings on `epyc12`. The 12-core CPU is already spoken for by CI runners and agent processes. Distribute the embedding workload locally to the host executing the agent, leveraging Apple Silicon where available, and strictly throttle the Ollama CPU footprint on the EPYC hosts.
