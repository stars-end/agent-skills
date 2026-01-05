# Verification Plan

---

## Test Phases

### Phase 1: Unit Tests (Coordinator)

| Test | Command | Expected |
|------|---------|----------|
| Health check | `curl localhost:4105/global/health` | `{"healthy": true}` |
| Session create | `POST /session` | Session ID returned |
| Session list | `GET /session` | Array of sessions |
| Session message | `POST /session/:id/message` | Response with parts |

### Phase 2: Integration Tests (Slack → OpenCode)

| Test | Action | Verify |
|------|--------|--------|
| Event reception | Post `[TASK] bd-test` to Slack | Coordinator logs event |
| Session creation | Post task | Session created for bd-test |
| Worktree creation | Post `bd-xyz` task | `~/affordabot-worktrees/bd-xyz` exists |
| Response posting | Wait for completion | Reply in Slack thread |

### Phase 3: E2E Tests (Full Workflow)

| Test | Steps | Success Criteria |
|------|-------|------------------|
| Single task | Post → Work → Complete | PR created, issue closed |
| Parallel tasks | Post 2 tasks | Both complete, no conflict |
| Agent handoff | @epyc6 then @macmini | Both respond in thread |
| HITL approval | Trigger approval | Continues after "approve" |
| Jules routing | @jules + jules-ready + docs/ | Jules dispatch called |

---

## Automated Test Script

```python
#!/usr/bin/env python3
"""verify-coordinator.py - Automated coordinator tests."""

import subprocess
import requests
import time
import json

OPENCODE_URL = "http://localhost:4105"
SLACK_CHANNEL = "#affordabot-agents"

def test_opencode_health():
    """Test OpenCode server health."""
    resp = requests.get(f"{OPENCODE_URL}/global/health")
    assert resp.status_code == 200
    assert resp.json().get("healthy") == True
    print("✅ OpenCode health OK")

def test_session_create():
    """Test session creation."""
    resp = requests.post(
        f"{OPENCODE_URL}/session",
        json={"title": "Test session"}
    )
    assert resp.status_code == 200
    session_id = resp.json().get("id")
    assert session_id.startswith("ses_")
    print(f"✅ Session created: {session_id}")
    return session_id

def test_session_message(session_id):
    """Test sending message to session."""
    resp = requests.post(
        f"{OPENCODE_URL}/session/{session_id}/message",
        json={"parts": [{"type": "text", "text": "What is 2+2?"}]}
    )
    assert resp.status_code == 200
    print("✅ Message sent OK")

def test_worktree_creation():
    """Test worktree creation (manual trigger)."""
    import os
    worktree_path = os.path.expanduser("~/affordabot-worktrees/bd-test-verify")
    # This would be triggered by coordinator
    # For now, check if directory structure exists
    assert os.path.isdir(os.path.expanduser("~/affordabot-worktrees"))
    print("✅ Worktree directory exists")

def test_beads_sync():
    """Test Beads sync without conflicts."""
    result = subprocess.run(
        ["bd", "sync"],
        capture_output=True, text=True,
        cwd=os.path.expanduser("~/affordabot")
    )
    assert result.returncode == 0
    print("✅ Beads sync OK")

if __name__ == "__main__":
    print("=== Coordinator Verification ===")
    test_opencode_health()
    session_id = test_session_create()
    test_session_message(session_id)
    test_worktree_creation()
    test_beads_sync()
    print("\n=== All Tests Passed ===")
```

---

## Manual Checklist

### Pre-Deployment

- [ ] `dx-check` passes on epyc6
- [ ] `dx-check` passes on macmini
- [ ] Slack channels created and bot invited
- [ ] SLACK_* env vars set in ~/.zshenv
- [ ] Beads merge driver configured

### Post-Deployment

- [ ] Post test message: `[TASK] bd-verify-001: echo hello`
- [ ] Verify response in thread
- [ ] Check `journalctl --user -u slack-coordinator -f`
- [ ] Check `systemctl --user status opencode-server`

### Multi-VM

- [ ] Post `@epyc6 bd-test` → epyc6 responds
- [ ] Post `@macmini bd-test` → macmini responds
- [ ] Post in thread `@macmini continue` → handoff works

---

## Success Criteria

| Criteria | Measurement |
|----------|-------------|
| Event reception | 100% of Slack tasks logged |
| Session creation | Session created within 5s |
| Worktree isolation | Each bd-xyz has own directory |
| No duplicates | Same task never dispatched twice |
| Machine stability | No crashes in 24 hours |
| Clean shutdown | All agents terminate on stop |

---

## Emergency Procedures

### Kill Switch

```bash
#!/usr/bin/env bash
# emergency-stop.sh
systemctl --user stop slack-coordinator
systemctl --user stop opencode-server
pkill -f "opencode"
echo "✅ All agent processes stopped"
```

### Rollback

```bash
# Disable services
systemctl --user disable slack-coordinator
systemctl --user disable opencode-server

# Check logs
journalctl --user -u slack-coordinator -n 100

# Report issue
# Include: journalctl output, last Slack messages, session IDs
```

---

## Monitoring

### Metrics to Watch

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU | 70% | 90% |
| Memory | 70% | 90% |
| Session Count | 5 | 10 |
| Response Time | 30s | 60s |

### Log Locations

| Service | Log Command |
|---------|-------------|
| Coordinator | `journalctl --user -u slack-coordinator -f` |
| OpenCode | `journalctl --user -u opencode-server -f` |
| Beads | `~/.beads/beads.log` |
