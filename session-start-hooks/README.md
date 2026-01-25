# Session Start Hooks

Platform-specific session start hooks for DX bootstrap integration.

See **[DX Bootstrap Contract](../DX_BOOTSTRAP_CONTRACT.md)** for the canonical bootstrap sequence.

---

## Available Hooks

### Claude Code: `claude-code-dx-bootstrap.sh`

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
1. Git sync with remote (optional, continues if fails)
2. Runs dx-doctor check (Makefile target or direct script)
3. Checks Agent Mail configuration status
4. Reports any issues (soft warnings, not blocking)

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

**Config**: `~/.antigravity/config.yaml`

```yaml
session:
  on_start:
    - git pull origin master
    - dx-check || true
    - bash -lc '[[ "${DX_BOOTSTRAP_COORDINATOR:-0}" == "1" ]] && dx-doctor || true'
```

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
