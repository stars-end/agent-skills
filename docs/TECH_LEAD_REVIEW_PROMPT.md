# Tech Lead Review: Global DX Index & Sync System (agent-skills-3vq)

## Context
We are upgrading our Agent DX (Developer Experience) to address "Context Window Pollution" and "Instruction Drift" across our multi-repo ecosystem (`agent-skills`, `prime-radiant`, `affordabot`).

Currently, `AGENTS.md` in each repo contains verbose, manually copied instructions for global workflows (Beads, Git, Safety). This wastes tokens and leads to inconsistent agent behavior when docs drift.

## The Proposal
Transition from **Manual Copy-Paste** to a **Managed Injection System** based on the [Vercel "Agents.md" pattern](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals).

### 1. The "High-Density Index" (The What)
Instead of full text, we inject a semantic routing map into `AGENTS.md`. This triggers the agent to *retrieve* the correct skill only when needed.

**Old:**
> "To start a feature, run /skill core/beads-workflow and select start-feature..." (50 tokens)

**New:**
> `Feature Workflow: start | sync | finish -> core/beads-workflow` (10 tokens)

### 2. The "Drift-Based Sync" (The How)
A robust, file-system-based mechanism ensures consistency across the "Canonical Agent Universe" (all VMs + all Agents).

*   **Source of Truth:** `~/agent-skills/fragments/GLOBAL_DX_INDEX.md` (Versioned).
*   **Target:** `<!-- GLOBAL_DX_INDEX -->` block in product repo `AGENTS.md`.
*   **Trigger:** `dx-check` (runs at session start) compares the `VERSION` tag in Source vs. Target.
    *   **Mismatch?** Blocks/Warns agent to run `dx-sync`.
*   **Resolution:** `dx-sync` script injects the new fragment. Agent commits the change (`chore: update dx index`).

## Implementation Plan (Epic: agent-skills-3vq)

1.  **Define Fragment:** Create the Vercel-style map in `agent-skills`.
2.  **Tooling:** Build `dx-sync` (injector) and update `dx-check` (drift detector).
3.  **Refactor:** Update all product repos (`prime-radiant`, `affordabot`) to use the injection markers and remove legacy text.

## Review Questions
1.  **Safety:** Does the `<!-- VERSION -->` comparison logic sufficiently prevent "downgrade loops" if a VM has a stale `agent-skills` repo? (Current plan: Warn if Source < Target).
2.  **Compatibility:** Is the "Pipe-Delimited Map" format intuitive enough for *all* our agents (Claude Code, Gemini, Antigravity) without fine-tuning?
3.  **DX:** Is the friction of "Warning -> Run Command -> Commit" acceptable for developers versus a silent background update? (We chose explicit to avoid "magic").

## Reference
- **Epic:** `agent-skills-3vq`
- **Inspiration:** Vercel Engineering Blog