# POC Run: Fresh-Agent DX Flow (bd-kb9r)

## Command Outputs

### ls -la AGENTS.md GEMINI.md
```
-rw-r--r--@ 1 fengning  wheel  20763 Feb  3 06:58 AGENTS.md
lrwxr-xr-x@ 1 fengning  wheel      9 Feb  3 06:58 GEMINI.md -> AGENTS.md
```

### rg -n "CANONICAL REPOSITORY RULES|NEVER commit|ALWAYS use worktrees" AGENTS.md | head -5
```
60:## ⚠️ CANONICAL REPOSITORY RULES (CRITICAL)
69:1. ❌ **NEVER commit directly to canonical repos**
71:3. ✅ **ALWAYS use worktrees for any change** (code, docs, config, etc.)
76:# Start new work - ALWAYS use worktrees
```

### git rev-parse --show-toplevel
```
/private/tmp/agents/bd-kb9r/agent-skills
```

### git rev-parse --abbrev-ref HEAD
```
feature-bd-kb9r
```

### git status --porcelain=v1
```
?? docs/poc_runs/
```
*(Note: Output shows the new directory about to be added)*

## Reflection

- **What confused you?**
    - The `dx-check` tool expects canonical clones on `main`, while these were on `master`. It's a minor naming mismatch but clear enough to fix.
    - Initializing the task required learning the specific `IsArtifact` and `ArtifactMetadata` requirements for this environment.

- **What went smoothly?**
    - `dx-worktree` is a powerful abstraction. It simplifies the multi-step process (create branch, create directory, add worktree, checkout) into a single, reliable command.
    - The `BEADS_DIR` environment variable being centrally managed makes cross-worktree issue tracking seamless.

- **What would reduce founder cognitive load?**
    - Auto-detecting the "canonical clone" state and refusing `git commit` at the hook level (which DCG/hooks already do) is the single most important safety net.
    - Having a standardized `docs/poc_runs/` convention ensures that even small experiments are captured with reproducible context.
