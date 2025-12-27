# Last Update: 2025-12-27

## System-Wide Framework Upgrade (V3 DX)

Completed forensic audit of 300+ commits across all repos. Identified systemic "Shadow Toil" around Beads sync, Lockfiles, and Submodules.

### 🛡️ Layer 1: Immutable Physics (Hooks)
- **State Recovery Hook:** Auto-runs `bd import`, `pnpm install`, and `submodule update` on checkout/merge.
- **Permission Sentinel:** Auto-enforces `chmod +x` on all scripts in `scripts/` and `bin/`.
- **Pre-Push Enforcer:** Blocks pushes if `make ci-lite` fails.

### 🧠 Layer 2: Cognitive Scaffolding (Skills)
- **Unified Lifecycle:** `start-feature`, `sync-feature --wip`, and `finish-feature`.
- **Golden Header:** Every `AGENTS.md` (and symlinked `GEMINI.md`) now bootstraps with `source ~/.bashrc && dx-check`.

### 🤖 Layer 3: Autonomous Oversight (Actions)
- **Lockfile Guardian:** Replaces passive validation with proactive detection of desynced lockfiles.
- **Night Watchman (WIP):** Spec finalized for GLM-4.6v vision-based autonomous QA missions.

### 🌍 Centralized Authority
- **llm-common/Makefile:** Standardized `ci-lite` and `test` targets for all products.
- **agent-skills:** Now the single source of truth for all Git hooks and GitHub Actions.

---
**Status:** Ready for Ring 2 Deployment (Hydration).