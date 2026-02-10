# External Beads Database Distribution Plan

**Status:** Draft | **Date:** 2026-01-31 | **POC:** agent-skills-pe5 (validated)

---

## Executive Summary

Distribute external beads database via `BEADS_DIR` environment variable across all VMs and agent IDEs to eliminate rebase conflicts caused by `.beads/` files in code repositories.

**Key Benefits:**
- Zero rebase conflicts on beads files
- Single source of truth for all issues
- Clean git history in code repos
- Cross-VM issue synchronization

---

## Target Environment

### VMs

| VM | User | Purpose | Current BEADS_DIR |
|----|------|---------|-------------------|
| homedesktop-wsl | fengning | Primary dev, DCG, CASS | TBD |
| macmini | fengning | macOS builds, iOS | TBD |
| epyc6 | feng | GPU work, ML training | TBD |

### Agent IDEs

| IDE | Primary VM | Config Location | Status |
|-----|------------|-----------------|--------|
| Claude Code | homedesktop-wsl | `cc-glm` alias | ✅ Active |
| Antigravity | homedesktop-wsl | `~/.gemini/antigravity/mcp_config.json` (MCP) | ✅ Active |
| Codex CLI | homedesktop-wsl | `~/.codex/config.toml` | ✅ Active |
| Gemini CLI | homedesktop-wsl | `~/.gemini-cli/config.json` | ✅ Active |
| OpenCode | epyc6 | systemd service | ✅ Active |

### Product Repos

| Repo | Current .beads/ | Migration Priority |
|------|-----------------|-------------------|
| agent-skills | `~/.agent/skills/.beads/` | P0 (reference implementation) |
| prime-radiant-ai | `.beads/` | P1 |
| affordabot | `.beads/` | P1 |
| llm-common | `.beads/` | P2 |

---

## Architecture

### Single Central Database

```
~/bd/.beads/                          (BEADS_DIR points here)
├── beads.db                          (SQLite database)
├── issues.jsonl                      (Export format)
├── config.yaml                       (Beads config)
└── .git/                             (For multi-VM sync)
```

### Environment Variable

```bash
export BEADS_DIR="$HOME/bd/.beads"
```

- Set in shell profile (`~/.bashrc` or `~/.zshrc`)
- Respected by all `bd` commands
- Overrides local `.beads/` detection

### Multi-VM Sync (Optional)

```
git@github.com:stars-end/bd.git
├── master branch                     (Live issues)
└── beads-sync branch                 (Optional sync-branch mode)
```

---

## Implementation Plan

### Phase 1: Central Database Setup (P0)

**Execute on primary VM (homedesktop-wsl):**

```bash
# 1. Create central database
mkdir -p ~/bd
cd ~/bd
git init
bd init                    # Auto-detects "bd" prefix
git add .beads/
git commit -m "Initialize central beads database"

# 2. Create GitHub repo (optional, for multi-VM sync)
gh repo create stars-end/bd --private --description "Central beads database for all VMs"
git remote add origin git@github.com:stars-end/bd.git
git push -u origin master

# 3. Verify
echo $BEADS_DIR            # Should be empty (not set yet)
cd ~/prime-radiant-ai
bd list                    # Should show "no beads database" or local db
```

### Phase 2: dx-hydrate.sh Integration (P0)

**Add to `scripts/dx-hydrate.sh`:**

```bash
# After line 3.6 (Beads merge driver setup)

# 3.7 External Beads Database (BEADS_DIR)
echo -e "${GREEN} -> Setting up external beads database...${RESET}"
BD_DIR="$HOME/bd"

if [ ! -d "$BD_DIR/.beads" ]; then
    echo "   Creating central beads database at $BD_DIR..."
    mkdir -p "$BD_DIR"
    (
        cd "$BD_DIR"
        if [ ! -f ".beads/beads.db" ]; then
            git init
            bd init
            # Initial commit
            git add .beads/
            git commit -m "Initialize central beads database"
        fi
    )
else
    echo "   ✅ Central beads database exists"
fi

# Export BEADS_DIR for current session
export BEADS_DIR="$BD_DIR/.beads"

# Add to shell profile if not already present
for RC_FILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$RC_FILE" ] && ! grep -q "BEADS_DIR" "$RC_FILE"; then
        echo "" >> "$RC_FILE"
        echo "# External Beads Database (managed by dx-hydrate)" >> "$RC_FILE"
        echo "export BEADS_DIR=\"$BD_DIR/.beads\"" >> "$RC_FILE"
        echo "   Added BEADS_DIR to $RC_FILE"
    fi
done
```

### Phase 3: dx-check.sh Verification (P1)

**Add to `scripts/dx-check.sh`:**

```bash
# After auto-checkpoint checks (around line 85)

# External Beads Database check
echo -e "${BLUE}🩺 Checking external beads database...${RESET}"
BD_DIR="$HOME/bd"

if [ -z "$BEADS_DIR" ]; then
    echo -e "${RED}❌ BEADS_DIR not set${RESET}"
    echo "   Fix: Run dx-hydrate.sh"
    needs_fix=1
elif [ "$BEADS_DIR" != "$BD_DIR/.beads" ]; then
    echo -e "${YELLOW}⚠️  BEADS_DIR points to non-standard location: $BEADS_DIR${RESET}"
    echo "   Standard: $BD_DIR/.beads"
else
    echo "   ✅ BEADS_DIR = $BEADS_DIR"
fi

# Verify database exists
if [ ! -f "$BEADS_DIR/beads.db" ]; then
    echo -e "${RED}❌ Beads database not found at $BEADS_DIR${RESET}"
    echo "   Fix: Run dx-hydrate.sh"
    needs_fix=1
else
    echo "   ✅ Database exists"
fi
```

### Phase 4: Agent IDE Session Hooks (P1)

#### Claude Code

**Update `.claude/hooks/SessionStart/dx-bootstrap.sh`:**

```bash
#!/bin/bash
# Ensure BEADS_DIR is set for Claude Code sessions
if [ -z "$BEADS_DIR" ]; then
    export BEADS_DIR="$HOME/bd/.beads"
fi

# Verify beads is accessible
if ! command -v bd >/dev/null 2>&1; then
    echo "⚠️  bd CLI not found. Issues tracking unavailable."
elif [ ! -f "$BEADS_DIR/beads.db" ]; then
    echo "⚠️  BEADS_DIR database not found. Run dx-hydrate.sh"
fi
```

#### Antigravity

Antigravity session-start hook configuration is not standardized here.

Recommended workaround:

- Set `BEADS_DIR` in your shell profile (`~/.zshrc`, `~/.bashrc`) so Antigravity inherits the environment.
- If needed, run: `export BEADS_DIR="$HOME/bd/.beads"` in the terminal you launch Antigravity from.

#### Codex CLI

**Update `~/.codex/config.toml`:**

```toml
[session]
on_start = ["bash -c 'export BEADS_DIR=\\\"\\$HOME/bd/.beads\\\"'"]
```

#### Gemini CLI

**Session start hook** (if supported):

```bash
export BEADS_DIR="$HOME/bd/.beads"
```

#### OpenCode

**No change needed** - inherits from systemd service environment:

```ini
[Service]
Environment="BEADS_DIR=/home/feng/bd/.beads"
```

### Phase 5: Multi-VM Distribution (P2)

#### VM: homedesktop-wsl (Primary)

**Execute:**
```bash
cd ~/agent-skills
./scripts/dx-hydrate.sh
./scripts/dx-check.sh
```

**Expected:**
- Creates `~/bd/.beads/`
- Adds BEADS_DIR to `~/.bashrc`
- All subsequent `bd` commands use central DB

#### VM: macmini

**Execute:**
```bash
cd ~/agent-skills
./scripts/dx-hydrate.sh
./scripts/dx-check.sh

# Clone central database if exists on GitHub
if gh repo view stars-end/bd >/dev/null 2>&1; then
    git clone git@github.com:stars-end/bd.git ~/bd
fi
```

#### VM: epyc6

**Execute:**
```bash
cd ~/agent-skills
./scripts/dx-hydrate.sh
./scripts/dx-check.sh

# Clone central database if exists on GitHub
if gh repo view stars-end/bd >/dev/null 2>&1; then
    git clone git@github.com:stars-end/bd.git ~/bd
fi

# Restart OpenCode service to pick up BEADS_DIR
systemctl --user restart opencode
```

### Phase 6: Migration of Existing Issues (P2)

**Decision:** Keep existing `.beads/` in place. Natural migration approach:

1. **Old `.beads/` becomes dormant** - BEADS_DIR takes precedence
2. **Old issues preserved** - accessible by unsetting BEADS_DIR
3. **No active migration needed** - new issues go to central DB
4. **Optional migration** - use `bd export` / `bd import` if desired

**Optional manual migration (if needed):**

```bash
# Export from old location
cd ~/prime-radiant-ai
unset BEADS_DIR
bd export -o /tmp/prime-radiant-ai-issues.jsonl

# Import to central DB
export BEADS_DIR="$HOME/bd/.beads"
bd import /tmp/prime-radiant-ai-issues.jsonl
```

---

## Verification Checklist

### Per-VM Verification

Run after setup:

```bash
# 1. Check BEADS_DIR is set
echo "BEADS_DIR = $BEADS_DIR"
# Expected: /home/$USER/bd/.beads

# 2. Check database exists
ls -la $BEADS_DIR/beads.db
# Expected: File exists

# 3. Verify bd uses external DB
cd ~/prime-radiant-ai
bd create "test-external-db-$(hostname)" -t task
# Expected: Creates issue with "bd-" prefix

# 4. Verify no changes in code repo
git status --porcelain | grep "\.beads"
# Expected: No output (clean)

# 5. Run dx-check
cd ~/agent-skills
./scripts/dx-check.sh
# Expected: All checks pass
```

### Cross-VM Verification (after GitHub sync)

```bash
# On homedesktop-wsl
cd ~/bd
bd create "cross-vm-test" -t task
git add .beads/
git commit -m "Add cross-vm test issue"
git push

# On macmini
cd ~/bd
git pull
bd list | grep "cross-vm-test"
# Expected: Shows the issue
```

---

## Rollback Plan

If issues arise:

### Per-VM Rollback

```bash
# Unset BEADS_DIR
unset BEADS_DIR
# Remove from shell profile
sed -i '/BEADS_DIR/d' ~/.bashrc
sed -i '/BEADS_DIR/d' ~/.zshrc

# Resume using local .beads/
cd ~/prime-radiant-ai
bd list  # Uses local .beads/
```

### Full Rollback

```bash
# Remove central database
rm -rf ~/bd

# Re-run dx-hydrate without BEADS_DIR section
# (or manually edit dx-hydrate.sh to remove Phase 2)
```

---

## Success Criteria

| Criterion | How to Verify |
|-----------|---------------|
| BEADS_DIR set on all VMs | `echo $BEADS_DIR` shows `~/bd/.beads` |
| dx-check passes | `./scripts/dx-check.sh` returns 0 |
| Issues use "bd-" prefix | `bd create` creates `bd-xxx` issues |
| Code repos stay clean | `git status` shows no `.beads/` changes |
| Cross-VM sync works | Issue created on VM1 appears on VM2 after `git pull` |
| All agent IDEs respect BEADS_DIR | Test `bd list` from each IDE |

---

## Open Questions

| Question | Proposed Answer | Decision Needed |
|----------|-----------------|-----------------|
| GitHub repo public or private? | Private - issues may contain context | Confirm |
| Sync method? | Manual `git push/pull` via `bd sync` | Confirm |
| Migration of old issues? | Keep in place, natural migration | Confirm |
| Issue prefix? | Use default "bd" from directory name | Confirmed |
| Backup strategy? | GitHub repo + periodic `bd export` | TBD |

---

## Dependencies

| Item | Status | Notes |
|------|--------|-------|
| beads BEADS_DIR support | ✅ Official | See ~/beads/docs/WORKTREES.md |
| dx-hydrate.sh | ✅ Exists | Add Phase 2 code |
| dx-check.sh | ✅ Exists | Add Phase 3 code |
| GitHub repo | ⏳ TBD | Create when ready for multi-VM |
| Agent IDE hooks | ⏳ TBD | Per-IDE config updates |

---

## Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Central DB | 5 min | None |
| Phase 2: dx-hydrate | 15 min | Phase 1 |
| Phase 3: dx-check | 10 min | Phase 2 |
| Phase 4: IDE hooks | 20 min | Phase 2 |
| Phase 5: Multi-VM | 30 min | Phase 1-4, GitHub repo |
| Phase 6: Migration | Optional | Phase 5 |

**Total:** ~80 minutes (excluding Phase 6)

---

## Next Steps

1. **Review and approve this plan** - @fengning
2. **Create GitHub repo** (if multi-VM sync needed) - `gh repo create stars-end/bd --private`
3. **Implement Phase 2-3** - Update `scripts/dx-hydrate.sh` and `scripts/dx-check.sh`
4. **Test on homedesktop-wsl** - Run full verification checklist
5. **Roll out to macmini** - Remote execution or manual
6. **Roll out to epyc6** - Include OpenCode service restart
7. **Document in AGENTS.md** - Add BEADS_DIR section

---

**Document History:**
- 2026-01-31: Initial draft (POC validated per agent-skills-pe5)
