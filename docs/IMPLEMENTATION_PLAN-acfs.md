# Implementation Plan: ACFS Tool Adoption

**Epic**: bd-acfs (agent-skills-1c0)  
**Date**: 2026-01-14  
**Owner**: Antigravity  
**Research**: [docs/research-acfs.md](./research-acfs.md)

> **Update (2026-01-14 12:30)**: bd-v1jo (lib/fleet) is **COMPLETE** and merged to master.
> The lib/fleet integration points in Phases 2.4 and 3.5 are now **ready to implement**.

---

## Goal

Adopt high-value tools from the ACFS repository into our agent-skills infrastructure:
1. **DCG** - Replace git-safety-guard with superior Rust-based safety hook
2. **BV** - Add Beads Viewer for human QoL and robot-plan API
3. **NTM** - Evaluate for local multi-agent orchestration
4. (Future) **CASS** - Pilot for cross-session knowledge mining

---

## Phase 1: DCG Adoption (P0) - `bd-acfs.1`

**Goal**: Replace git-safety-guard with DCG on all VMs

### Tasks

#### 1.1 Install DCG on all VMs
```bash
# On each VM (homedesktop-wsl, epyc6, macmini)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh?$(date +%s)" | bash
```

#### 1.2 Configure Claude Code hook
Update `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "dcg"}]
      }
    ]
  }
}
```

#### 1.3 Configure Gemini CLI hook
Update `~/.gemini/settings.json` (if exists) with DCG hook

#### 1.4 Enable modular packs
Configure `~/.config/dcg/config.toml`:
```toml
[packs]
enabled = [
  "database.postgresql",   # Protect Railway DB
  "containers.docker",     # If using Docker
]
```

#### 1.5 Archive git-safety-guard
- Move `~/agent-skills/git-safety-guard/` to `~/agent-skills/git-safety-guard.deprecated/`
- Update SKILL.md to point to DCG
- Update vm-bootstrap to install DCG instead

#### 1.6 Update documentation
- Update AGENTS.md to reference DCG
- Add DCG to vm-bootstrap verification checks

### Verification
```bash
# Test DCG blocks dangerous command
echo '{"tool": "Bash", "input": {"command": "git reset --hard"}}' | dcg
# Should output: {"decision": "block", ...}

# Test safe command allowed
echo '{"tool": "Bash", "input": {"command": "git status"}}' | dcg
# Should output: {"decision": "allow"}
```

---

## Phase 2: BV Adoption (P0) - `bd-acfs.2`

**Goal**: Install Beads Viewer and integrate with workflows

### Tasks

#### 2.1 Install BV on all VMs
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash
```

#### 2.2 Test robot protocol
```bash
cd ~/affordabot
bv --robot-plan           # Should return next actionable task
bv --robot-insights       # Should return graph metrics JSON
```

#### 2.3 Create bv-integration skill
Create `~/agent-skills/bv-integration/SKILL.md`:
```markdown
---
name: bv-integration
description: Use Beads Viewer for task selection and graph insights
---

# BV Integration

## Auto-Select Next Task
Instead of `bd list --open`, use:
\`\`\`bash
bv --robot-plan
\`\`\`

Returns structured JSON with:
- `next`: ID of highest-impact unblocked task
- `unblocks`: Number of tasks unblocked by completing it
- `reason`: Why this task was selected
```

#### 2.4 lib/fleet integration ✅ READY

**Status**: lib/fleet (bd-v1jo) is COMPLETE. `lib/fleet/dispatcher.py` exists.

Add method to `FleetDispatcher` class in `lib/fleet/dispatcher.py`:
```python
import subprocess
import json
from pathlib import Path
from typing import Optional

# Add to FleetDispatcher class:
def auto_select_task(self, repo: str = "affordabot") -> Optional[str]:
    """Use BV robot-plan to select next task for auto-dispatch.
    
    Returns the Beads ID of the highest-impact unblocked task,
    or None if BV is not installed or fails.
    """
    try:
        result = subprocess.run(
            ["bv", "--robot-plan"],
            capture_output=True, 
            text=True, 
            timeout=10,
            cwd=str(Path.home() / repo)  # Correct: Path.home() not f"~/{repo}"
        )
        if result.returncode == 0:
            plan = json.loads(result.stdout)
            return plan.get("next")
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        # BV not installed or failed - gracefully degrade
        pass
    return None
```


#### 2.4b Update nightly_dispatch.py
Consider updating `scripts/nightly_dispatch.py` to use BV for smarter task selection:
```python
# Instead of simple issue fetching, use:
dispatcher = FleetDispatcher()
next_task = dispatcher.auto_select_task(repo="affordabot")
if next_task:
    dispatcher.dispatch(beads_id=next_task, ...)
```

#### 2.5 Update beads-workflow skill
Add BV commands to `~/agent-skills/beads-workflow/SKILL.md`

#### 2.6 Update vm-bootstrap
Add BV to tool verification in `vm-bootstrap/SKILL.md`

### Verification
```bash
# TUI works
bv

# Robot mode works
bv --robot-plan | jq .next
```

---

## Phase 3: NTM Evaluation (P1) - `bd-acfs.3`

**Goal**: Install NTM on epyc6 for local multi-agent orchestration

### Tasks

#### 3.1 Install NTM on epyc6 only (pilot)
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash
```

#### 3.2 Test basic workflows
```bash
# Create project
ntm quick test-project --template=python

# Spawn agents
ntm spawn test-project --cc=2 --cod=1

# View dashboard
ntm dashboard test-project

# Broadcast prompt
ntm send test-project --cc "analyze the codebase"
```

#### 3.3 Document findings
Create `~/agent-skills/docs/ntm-evaluation.md` with:
- What worked well
- What didn't integrate with our workflow
- Recommendation to adopt/skip

#### 3.4 (If adopting) Create ntm-orchestration skill
```markdown
---
name: ntm-orchestration
description: Local multi-agent orchestration with NTM
---
```

#### 3.5 (If adopting) Add NtmBackend for lib/fleet ✅ READY

**Status**: lib/fleet backend interface is defined in `lib/fleet/backends/base.py`.

Create `~/agent-skills/lib/fleet/backends/ntm.py`:
```python
"""NTM backend for local tmux-based dispatch."""
from .base import BackendBase, HealthStatus, SessionStatus, SessionInfo
import subprocess
import json

class NtmBackend(BackendBase):
    """Local tmux-based dispatch via NTM."""
    
    def __init__(self, name: str = "local-ntm", project: str = "dev"):
        super().__init__(name, "ntm")
        self.project = project
    
    def check_health(self) -> HealthStatus:
        result = subprocess.run(["ntm", "status", self.project, "--json"], 
                                capture_output=True, text=True)
        if result.returncode == 0:
            return HealthStatus.HEALTHY
        return HealthStatus.SERVER_UNREACHABLE
    
    def dispatch(self, beads_id: str, prompt: str, worktree_path: str,
                 system_prompt: str | None = None) -> str:
        # Spawn a Claude Code agent in tmux pane
        result = subprocess.run(
            ["ntm", "spawn", self.project, "--cc=1", "--name", beads_id],
            capture_output=True, text=True
        )
        session_id = f"{self.project}-{beads_id}"
        # Send initial prompt
        subprocess.run(["ntm", "send", self.project, "--cc", prompt])
        return session_id
    
    # ... implement other abstract methods
```

See `lib/fleet/backends/opencode.py` for full reference implementation.

### Verification
- Human can monitor agents via dashboard
- Conflict detection works
- Session persistence on SSH disconnect

---

## Phase 4: CASS Pilot (P2) - `bd-acfs.4`

**Goal**: Pilot CASS on epyc6 to evaluate cross-session search value

### Tasks

#### 4.1 Install CASS on epyc6 only
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash
```

#### 4.2 Configure indexing
```bash
cass index --all  # Index all agent sessions
cass watch        # Start background indexer
```

#### 4.3 Use for 1 month
- Document useful searches
- Track times "I solved this before" was helpful
- Note performance issues

#### 4.4 Evaluate decision
After 1 month, decide:
- **Adopt**: Roll out to all VMs
- **Skip**: Document why and archive

#### 4.5 (If adopting) llm-common integration
Consider sharing MiniLM embedding infrastructure with llm-common retrieval

---

## Proposed Changes Summary

### New Files

| Path | Description |
|------|-------------|
| `docs/research-acfs.md` | Research documentation (this epic) |
| `docs/IMPLEMENTATION_PLAN-acfs.md` | This implementation plan |
| `bv-integration/SKILL.md` | BV integration skill |
| `docs/ntm-evaluation.md` | NTM evaluation results (Phase 3) |

### Modified Files

| Path | Change |
|------|--------|
| `git-safety-guard/SKILL.md` | Deprecation notice, point to DCG |
| `vm-bootstrap/SKILL.md` | Add DCG, BV to installation and verification |
| `beads-workflow/SKILL.md` | Add BV robot-plan commands |
| `lib/fleet/dispatcher.py` | Add auto_select_task() with BV (if lib/fleet complete) |

### Archived Files

| Path | Reason |
|------|--------|
| `git-safety-guard.deprecated/` | Replaced by DCG |

---

## Verification Plan

### Agent-Driven E2E Tests

Add to `scripts/test_e2e_comprehensive.py`:

```python
# =============================================================================
# DCG Safety Tests
# =============================================================================

def test_dcg_installed_all_vms():
    """Verify DCG is installed on all VMs."""
    for vm in ["homedesktop-wsl", "epyc6", "macmini"]:
        result = subprocess.run(
            ["ssh", vm, "which dcg && dcg --version"],
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, f"DCG not installed on {vm}"

def test_dcg_blocks_dangerous_command():
    """DCG blocks git reset --hard."""
    test_input = '{"tool": "Bash", "input": {"command": "git reset --hard"}}'
    result = subprocess.run(
        ["dcg"], input=test_input, capture_output=True, text=True
    )
    output = json.loads(result.stdout)
    assert output.get("decision") == "block"

def test_dcg_allows_safe_command():
    """DCG allows git status."""
    test_input = '{"tool": "Bash", "input": {"command": "git status"}}'
    result = subprocess.run(
        ["dcg"], input=test_input, capture_output=True, text=True
    )
    output = json.loads(result.stdout)
    assert output.get("decision") == "allow"

# =============================================================================
# BV Integration Tests
# =============================================================================

def test_bv_installed_all_vms():
    """Verify BV is installed on all VMs."""
    for vm in ["homedesktop-wsl", "epyc6", "macmini"]:
        result = subprocess.run(
            ["ssh", vm, "which bv && bv --version"],
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, f"BV not installed on {vm}"

def test_bv_robot_plan_returns_valid_json():
    """BV robot-plan returns valid JSON."""
    result = subprocess.run(
        ["bv", "--robot-plan"],
        cwd=Path.home() / "affordabot",
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0
    plan = json.loads(result.stdout)
    assert "next" in plan or "error" in plan

def test_bv_robot_plan_returns_valid_beads_id():
    """BV robot-plan returns a valid Beads ID."""
    result = subprocess.run(
        ["bv", "--robot-plan"],
        cwd=Path.home() / "affordabot",
        capture_output=True, text=True
    )
    if result.returncode == 0:
        plan = json.loads(result.stdout)
        if plan.get("next"):
            # Verify task exists
            bd_result = subprocess.run(
                ["bd", "show", plan["next"]],
                cwd=Path.home() / "affordabot",
                capture_output=True
            )
            assert bd_result.returncode == 0, f"BV returned invalid task: {plan['next']}"

# =============================================================================
# lib/fleet Integration Tests
# =============================================================================

def test_fleet_dispatcher_auto_select_task():
    """FleetDispatcher.auto_select_task works with BV."""
    sys.path.insert(0, str(Path.home() / "agent-skills"))
    from lib.fleet import FleetDispatcher
    
    dispatcher = FleetDispatcher()
    # Should not crash, may return None if BV not installed or no tasks
    task = dispatcher.auto_select_task("affordabot")
    if task:
        assert task.startswith("affordabot-") or task.startswith("bd-")

def test_fleet_dispatcher_still_works_without_bv():
    """FleetDispatcher works normally even if BV fails."""
    sys.path.insert(0, str(Path.home() / "agent-skills"))
    from lib.fleet import FleetDispatcher
    
    dispatcher = FleetDispatcher()
    # Standard dispatch should work regardless of BV
    # (This is a smoke test, not full dispatch)
    assert dispatcher is not None
    assert hasattr(dispatcher, "dispatch")
```

### Manual Verification Steps

#### Phase 1: DCG

```bash
# 1. Verify installation on all VMs
for vm in homedesktop-wsl epyc6 macmini; do
    echo "=== $vm ==="
    ssh $vm "which dcg && dcg --version" || echo "❌ FAIL"
done

# 2. Verify blocking works
echo '{"tool": "Bash", "input": {"command": "rm -rf /"}}' | dcg | jq .decision
# Expected: "block"

# 3. Verify hook configured for Claude Code
cat ~/.claude/settings.json | jq '.hooks.PreToolUse'
# Should show dcg hook
```

#### Phase 2: BV

```bash
# 1. Verify installation
which bv && bv --version

# 2. Robot protocol works
cd ~/affordabot && bv --robot-plan | jq .

# 3. Insights work
cd ~/affordabot && bv --robot-insights | jq .bottlenecks
```

#### Phase 3: lib/fleet Integration

```bash
# Test auto_select_task (after adding to dispatcher.py)
cd ~/agent-skills
python3 -c "
from lib.fleet import FleetDispatcher
d = FleetDispatcher()
task = d.auto_select_task('affordabot')
print(f'Next task: {task}')
"
```

---

## Timeline (Updated)

| Phase | Task | Duration | Depends On | Parallel? |
|-------|------|----------|------------|-----------|
| 1 | DCG Adoption | 2 hours | - | ✅ Yes |
| 2 | BV Adoption | 2 hours | - | ✅ Yes |
| 3 | NTM Evaluation | 1 week | - | ✅ Yes |
| 4 | CASS Pilot | 1 month | - | ✅ Yes |

**Note:** Phases 1-4 are now independent and can run in parallel.

---

## Rollback Plan

### DCG Rollback
```bash
# Remove hook from agent configs
jq 'del(.hooks.PreToolUse)' ~/.claude/settings.json > tmp && mv tmp ~/.claude/settings.json

# Restore git-safety-guard if needed
mv ~/agent-skills/git-safety-guard.deprecated ~/agent-skills/git-safety-guard
```

### BV Rollback
BV is additive. Just don't use `--robot-plan`. Fall back to `bd ready`.

### NTM/CASS Rollback
Pilot on epyc6 only. Uninstall with:
```bash
rm $(which ntm)  # or cass
```

---

## Skills Created

| Skill | Path | Purpose |
|-------|------|---------|
| `dcg-safety` | `~/agent-skills/dcg-safety/SKILL.md` | Teach agents about DCG blocking |
| `bv-integration` | `~/agent-skills/bv-integration/SKILL.md` | Teach agents to use robot-plan |

Both follow agentskills.io specification and work with all agents (Claude Code, Antigravity, Gemini CLI, Codex CLI).

