# Component Status

**Last Verified:** 2026-01-04 13:55 PST

---

## Verified Working ✅

| Component | Evidence | Location |
|-----------|----------|----------|
| **OpenCode Server** | systemd active, 421MB memory | epyc6:4105 |
| **Slack Coordinator** | Logs show event reception | epyc6 systemd |
| **Slack MCP** | `opencode.json` configured | `~/.config/opencode/` |
| **Socket Mode** | Events received in logs | slack-coordinator.py |
| **Session Creation** | HTTP 200 OK in logs | OpenCode API |
| **Beads Merge Driver** | `git config --global` | epyc6, macmini, homedesktop |

**Logs Evidence:**
```
Jan 04 16:53:09 - Received task in #affordabot-agents: [TASK] bd-test-004
Jan 04 16:53:10 - HTTP POST http://localhost:4105/session "HTTP/1.1 200 OK"
Jan 04 16:54:00 - HTTP POST .../message "HTTP/1.1 200 OK"
```

---

## Code Exists, NOT TESTED ⚠️

| Component | Code Location | Gaps |
|-----------|---------------|------|
| **Jules Routing** | `slack-coordinator.py:65-108` | Three-gate not tested |
| **HITL Approval** | `slack-coordinator.py:142-193` | Approval flow not tested |
| **Git Worktree Commands** | Conceptual only | Not in coordinator |

---

## NOT IMPLEMENTED ❌

| Component | Gap | Priority |
|-----------|-----|----------|
| **Worktree Creation** | Coordinator doesn't create worktrees | P0 |
| **Session CWD** | Sessions run in default dir | P0 |
| **Multi-VM Routing** | @macmini not parsed | P1 |
| **Agent-to-Agent** | Thread @mention not routed | P3 |
| **dx-doctor** | No diagnostics | P2 |
| **Testing Automation** | Manual plan only | P4 |

---

## Partial ⚠️

| Component | What Works | What's Missing |
|-----------|------------|----------------|
| **dx-hydrate** | OpenCode install | Coordinator install, Slack tokens |
| **dx-check** | Basic checks | Coordinator health, session count |
| **Testing** | Manual plan | Automated scripts |
| **Deployment** | Manual scp/ssh | dx-deploy script |

---

## Full Component Matrix

| # | Component | Status | Code |
|---|-----------|--------|------|
| 1 | Beads | ✅ Working | bd CLI |
| 2 | Git Worktrees | ❌ Conceptual | - |
| 3 | Slack Socket Mode | ✅ Working | slack-coordinator.py |
| 4 | Slack MCP Server | ✅ Configured | opencode.json |
| 5 | OpenCode Server | ✅ Running | systemd |
| 6 | OpenCode Sessions | ✅ Basic | HTTP API |
| 7 | Jules | ⚠️ Code exists | slack-coordinator.py |
| 8 | Multi-VM Routing | ❌ Planned | - |
| 9 | Beads Merge Driver | ✅ Configured | git config |
| 10 | Agent-to-Agent | ❌ Not designed | - |
| 11 | Human-in-Loop | ⚠️ Code exists | slack-coordinator.py |
| 12 | Tailscale | ✅ Connected | All VMs |
| 13 | gh CLI | ⚠️ Mentioned | Jules only |
| 14 | dx-hydrate | ⚠️ Partial | dx-hydrate.sh |
| 15 | dx-check | ⚠️ Partial | dx-check.sh |
| 16 | dx-doctor | ❌ Missing | - |
| 17 | Testing | ⚠️ Manual | VERIFICATION_PLAN.md |
