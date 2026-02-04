## DX Global Constraints (Always-On)

1) **NO WRITES** in canonical clones: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
2) **Worktree first**: `dx-worktree create <id> <repo>`
3) **Before "done"**: run `~/agent-skills/scripts/dx-verify-clean.sh` (must PASS)
4) For full rules, read repo `AGENTS.md` / `GEMINI.md`.
