# POC Run: Fresh-Agent DX Flow Test

**Branch**: `feature-poc-fresh-agent-test`
**Date**: 2026-02-03
**Agent**: Claude Code (cc-glm)
**Purpose**: Test fresh-agent DX flow using only what the repo auto-provides

---

## Command Outputs

### 1. File listing for AGENTS.md and GEMINI.md
```bash
$ ls -la AGENTS.md GEMINI.md
-rw-r--r--@ 1 fengning  staff  20817 Feb  3 09:18 AGENTS.md
lrwxr-xr-x@ 1 fengning  staff      9 Feb  1 09:12 GEMINI.md -> AGENTS.md
```

### 2. Canonical rules search
```bash
$ rg -n "CANONICAL REPOSITORY RULES|NEVER commit|ALWAYS use worktrees" AGENTS.md | head -5
60:## ⚠️ CANONICAL REPOSITORY RULES (CRITICAL)
69:1. ❌ **NEVER commit directly to canonical repos**
71:3. ✅ **ALWAYS use worktrees for any change** (code, docs, config, etc.)
76:# Start new work - ALWAYS use worktrees (use dx-worktree; do not run `git worktree` directly)
```

### 3. Git toplevel (from worktree)
```bash
$ git rev-parse --show-toplevel
/private/tmp/agents/poc-fresh-agent-test/agent-skills
```

### 4. Current branch (from worktree)
```bash
$ git rev-parse --abbrev-ref HEAD
feature-poc-fresh-agent-test
```

### 5. Git status porcelain (from worktree)
```bash
$ git status --porcelain=v1
```
(empty - no uncommitted changes yet)

---

## Reflections

### What Confused Me
- **Shell cwd reset behavior**: After running `git` commands from the worktree, the shell automatically reset back to the canonical repo (`~/agent-skills`). This wasn't explicitly documented in AGENTS.md and could be confusing when trying to work entirely from the worktree context.

- **Branch name transformation**: When I created the worktree with `dx-worktree create poc-fresh-agent-test agent-skills`, the actual branch name created was `feature-poc-fresh-agent-test` (with `feature-` prefix). The prefix behavior isn't documented in the AGENTS.md workflow section.

- **Worktree path structure**: The worktree was created at `/tmp/agents/poc-fresh-agent-test/agent-skills` - the nesting of `agent-skills` inside the branch-named directory is logical but not immediately obvious from the docs which show `/tmp/agents/bd-xxxx/prime-radiant-ai`.

- **GEMINI.md is a symlink**: The file listing revealed `GEMINI.md -> AGENTS.md` - this is a sensible deduplication pattern but not documented. It raises the question: are there other agent-specific symlinks?

### What Went Smoothly
- **`dx-worktree` command**: The `dx-worktree create` subcommand worked perfectly and is well-integrated. No manual `git worktree` commands needed.

- **Canonical repo rules are clear**: The "NEVER commit / ALWAYS use worktrees" rules are prominently displayed and easy to find with the provided ripgrep pattern.

- **Documentation structure**: AGENTS.md is comprehensive and well-organized. The canonical rules section is prominently placed (line 60) and uses clear visual indicators (⚠️, ❌, ✅).

- **Single source of truth**: The symlink pattern (GEMINI.md -> AGENTS.md) ensures documentation consistency across agent types without duplication.

### What Would Reduce Founder Cognitive Load

1. **Document the `feature-` prefix behavior**: Update AGENTS.md to explain that `dx-worktree create` automatically adds a `feature-` prefix to branch names, or remove this auto-prefix if it adds unnecessary complexity.

2. **Add worktree verification section**: Include a quick "am I in the right place?" checklist:
   ```bash
   # Verify you're in a worktree
   git rev-parse --show-toplevel | grep -q /tmp/agents/
   ```

3. **Clarify shell behavior**: Document that the shell cwd resets after git commands from worktrees, and provide the canonical pattern for staying in worktree context:
   ```bash
   cd /tmp/agents/poc-fresh-agent-test/agent-skills && git status
   ```

4. **POC collision avoidance**: The `docs/poc_runs/` directory pattern is good, but consider adding a timestamp or agent identifier to prevent collisions when multiple POCs are run:
   ```bash
   docs/poc_runs/feature-poc-fresh-agent-test_2026-02-03_cc-glm.md
   ```

5. **Explicit directory structure diagram**: Expand the worktree docs with a visual tree:
   ```
   /tmp/agents/
   └── poc-fresh-agent-test/
       └── agent-skills/          <-- This is your worktree root
           ├── docs/
           ├── scripts/
           └── ...
   ```

6. **One-shot worktree entry**: Add a helper command or shell function to "cd into worktree by branch name":
   ```bash
   dx-worktree cd poc-fresh-agent-test  # Would cd to the worktree
   ```

---

## Summary

This POC successfully validated the worktree-based workflow. The canonical repo rules are effective at preventing direct commits to `~/agent-skills`. The `dx-worktree` tool works well but could benefit from additional documentation around its automatic behaviors (prefixing, directory structure, shell context).

**Overall assessment**: The DX flow is functional and safe, with opportunities to reduce cognitive load through better documentation of automatic behaviors and helper utilities for common worktree operations.
