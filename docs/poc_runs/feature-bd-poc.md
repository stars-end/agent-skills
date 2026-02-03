# POC Run: feature-bd-poc

## Outputs

### ls -la AGENTS.md GEMINI.md
```
-rw-r--r--@ 1 fengning  wheel  20817 Feb  3 09:45 AGENTS.md
lrwxr-xr-x@ 1 fengning  wheel      9 Feb  3 09:45 GEMINI.md -> AGENTS.md
```

### rg -n "CANONICAL REPOSITORY RULES|NEVER commit|ALWAYS use worktrees" AGENTS.md | head -5
```
60:## ⚠️ CANONICAL REPOSITORY RULES (CRITICAL)
69:1. ❌ **NEVER commit directly to canonical repos**
71:3. ✅ **ALWAYS use worktrees for any change** (code, docs, config, etc.)
76:# Start new work - ALWAYS use worktrees (use dx-worktree; do not run `git worktree` directly)
```

### git rev-parse --show-toplevel
```
/private/tmp/agents/bd-poc/agent-skills
```

### git rev-parse --abbrev-ref HEAD
```
feature-bd-poc
```

### git status --porcelain=v1
```
```

## Reflection
- Confused: `dx-check` expects canonical repos on `main`, but this repo is on `master`, which flags errors during a POC even when no changes are made.
- Smooth: `dx-worktree create` produced a ready worktree path without extra setup.
- Cognitive load reduction: provide a single `dx-poc-run` helper that creates the worktree, captures required command outputs, and writes the templated report file.
