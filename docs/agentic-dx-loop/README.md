# Agentic DX Loop Implementation

This epic implements a rigorous, tool-enforced workflow for AI agents working across the Stars-End ecosystem.

## Architecture: The Hybrid Guardrail

We use a 3-layer defense strategy:

1.  **Layer 1: Happy Path Skills (Lifecycle)**
    - `start-feature`: Setup context, branches, and stories.
    - `sync-feature`: The 'Save' button. Runs `ci-lite`.
    - `finish-feature`: The 'Handoff' button. Runs `verify-pr`.

2.  **Layer 2: The Physics (Hooks)**
    - `pre-push`: Enforces `ci-lite`. Prevents pushing broken code.

3.  **Layer 3: The Truth (Makefiles)**
    - Standardized targets (`ci-lite`, `verify-pr`) across all repos.

## Implementation Plan

Tracked in Beads Epic: `agent-skills-vnh`

1.  **Standardize llm-common** (Task 1): Add Makefile.
2.  **Standardize Casing** (Task 2): `docs/testing/stories`.
3.  **Implement Skills** (Task 3): `agent-skills/feature-lifecycle/`.
4.  **Enforce Hooks** (Task 4): Update `git-safety-guard`.
5.  **DX Bootstrap** (Task 5): `dx-check` alias.
6.  **Audit** (Task 6): `audit-stories.sh`.

