# Session Start Hooks

Cross-agent session start hooks for DX bootstrap integration.

Canonical entrypoint:

- `~/agent-skills/session-start-hooks/dx-bootstrap.sh`

---

## Available Hooks

### Cross-Agent Entrypoint: `dx-bootstrap.sh`

This is the canonical script that enforces "no canonical edits" (hard-stop) and then runs best-effort DX checks.

Manual test:
```bash
bash ~/agent-skills/session-start-hooks/dx-bootstrap.sh
```

Escape hatch (only to create/switch to a worktree or to remediate):
```bash
DX_CANONICAL_ACK=1 bash ~/agent-skills/session-start-hooks/dx-bootstrap.sh
```

### Claude Code (Per-Repo): `claude-code-dx-bootstrap.sh`

**Purpose**: Run dx-doctor check at session start to detect environment drift

**Installation**:
```bash
# Per-repo installation
cd ~/your-repo
mkdir -p .claude/hooks/SessionStart
cp ~/agent-skills/session-start-hooks/claude-code-dx-bootstrap.sh \
   .claude/hooks/SessionStart/dx-bootstrap.sh
chmod +x .claude/hooks/SessionStart/dx-bootstrap.sh
```

**What it does**:
Delegates to the cross-agent entrypoint `dx-bootstrap.sh` when present.

**Testing**:
```bash
# Trigger manually
.claude/hooks/SessionStart/dx-bootstrap.sh

# Or start new Claude Code session
claude
```

---

## Other Platforms

### Codex CLI

**Config**: `~/.codex/config.toml`

```toml
[session]
on_start = "bash ~/.agent/skills/session-start-hooks/dx-bootstrap.sh"
```

### Antigravity

Antigravity supports skills + MCP config (`~/.gemini/antigravity/mcp_config.json`), but session-start hook support is not currently standardized in this repo.

Recommended workaround:

1. Ensure the DX global constraints rail is installed (see `docs/IDE_SPECS.md`).
2. Run `bash ~/.agent/skills/session-start-hooks/dx-bootstrap.sh` manually before starting work.

### OpenCode

OpenCode is typically run as a service; it does not have a per-session "SessionStart" hook contract here.

DX enforcement still applies via:

- versioned git hooks (`.githooks/` + `core.hooksPath`)
- CI PR metadata enforcement (Feature-Key + Agent)

### Gemini

**TBD**: Awaiting Gemini session hook support

---

## Customization

**Per-repo overrides**: Edit `.claude/hooks/SessionStart/dx-bootstrap.sh` in your repo to customize behavior

**Example customizations**:
- Skip git pull: Comment out step 1
- Add repo-specific checks: Add commands after step 2
- Require passing dx-doctor: Change warnings to errors

---

## Troubleshooting

### Hook not running

**Check**:
```bash
# Verify hook exists and is executable
ls -la .claude/hooks/SessionStart/
```

**Fix**: Ensure hook is executable: `chmod +x .claude/hooks/SessionStart/*.sh`

### Blocked in a canonical repo

If you see an error about being in a canonical repo, create/switch to a worktree:

```bash
dx-worktree create <beads-id> <repo>
cd /tmp/agents/<beads-id>/<repo>
```

### dx-doctor not found

**Check**:
```bash
command -v dx-doctor || true
ls -la ~/.agent/skills/scripts/dx-doctor.sh
```

**Fix**: Install agent-skills:
```bash
git clone https://github.com/stars-end/agent-skills ~/.agent/skills
```

---

**Last Updated**: 2025-12-12
**Part of**: bd-3871 (DX bootstrap consistency)
