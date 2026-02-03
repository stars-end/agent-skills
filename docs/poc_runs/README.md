#+#+#+#+#+#+#+#+━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# POC Runs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Small “fresh agent” proof-of-work runs live here (one draft PR per run).

## Minimal POC Prompt (copy/paste)

Create a new file at `docs/poc_runs/poc_run.md` with:
- Output of: `ls -la AGENTS.md GEMINI.md`
- Output of: `rg -n "CANONICAL REPOSITORY RULES|NEVER commit|ALWAYS use worktrees" AGENTS.md | head -5`
- Output of: `git rev-parse --show-toplevel`
- Output of: `git rev-parse --abbrev-ref HEAD`
- Output of: `git status --porcelain=v1`
- Reflection (3 bullets):
  - What confused you?
  - What went smoothly?
  - What should change to reduce founder cognitive load?

Then open a **draft PR** with only that file changed.

## Notes

- Do not try to embed the commit hash of the commit that contains `poc_run.md` inside `poc_run.md` (self-referential).
