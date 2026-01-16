# OpenCode Dispatch Investigation - epyc6

## Context

You are investigating why OpenCode dispatches from the Nightly Fleet Dispatcher are not completing on this VM (epyc6). The dispatches log "SUCCESS" but no code changes or PRs are being created.

## Timeline of Issue

- **07:08 PST (2026-01-16)**: Nightly dispatcher ran and dispatched 3 bugs (bd-lxt8, bd-ffxr, bd-ov84)
- **08:45 PST**: 1.5 hours later, no PRs created
- **Symptom**: `feature-bd-lxt8` branch exists locally but has no new commits

## Your Mission

1. **Diagnose** why OpenCode isn't executing the dispatched tasks
2. **Fix** the issue if possible
3. **Test** by manually running a dispatch and confirming it creates a PR
4. **Report** findings back (post to #fleet-events or commit a doc)

---

## Step 1: Check OpenCode Server Health

```bash
# Is the process running?
ps aux | grep opencode | grep -v grep

# Check the port
lsof -i :4105

# Test health endpoint
curl -s http://localhost:4105/global/health

# Check recent logs
cat ~/.local/share/opencode/log/*.log 2>/dev/null | tail -50
```

**Known issue from logs:**
```
ERROR: Failed to start server on port 4105
```
Multiple restart attempts failed because port was in use.

---

## Step 2: Restart OpenCode (if needed)

If the server is unhealthy or stale (process from Jan 14):

```bash
# Kill existing process
pkill -f "opencode serve"

# Wait for port to free
sleep 2

# Verify port is free
lsof -i :4105  # Should show nothing

# Start fresh
nohup opencode serve --port 4105 --hostname 0.0.0.0 > ~/.local/share/opencode/log/startup.log 2>&1 &

# Verify
sleep 3
curl -s http://localhost:4105/global/health
```

---

## Step 3: Check Dispatch Mechanism

The dispatch flow is:
```
GH Actions → nightly_dispatch.py → dx-dispatch.py → FleetDispatcher → HTTP to OpenCode
```

Check if dispatches are reaching OpenCode:

```bash
# Check FleetDispatcher state
cat ~/.fleet-controller/dispatches.json

# Check if branch was created (proves dispatch reached OpenCode)
cd ~/prime-radiant-ai
git branch -a | grep -E "lxt8|ffxr|ov84"

# Check commits on the branch
git log feature-bd-lxt8 --not master --oneline
```

---

## Step 4: Test Manual Dispatch

Run a simple task manually to verify OpenCode is working:

```bash
cd ~/prime-radiant-ai

# Simple test - create a file
opencode run "Create a file called TEST_DISPATCH.md with the content 'Dispatch test successful at $(date)'. Commit it with message 'chore: test dispatch'"

# Check if it worked
git log -1 --oneline
cat TEST_DISPATCH.md
```

---

## Step 5: Test Full Dispatch Flow

Use dx-dispatch to simulate what the nightly dispatcher does:

```bash
cd ~/agent-skills

# Dispatch a real issue
python3 scripts/dx-dispatch.py epyc6 "In ~/prime-radiant-ai, check the status of the project and report any issues" --repo prime-radiant-ai --beads bd-test-dispatch
```

Monitor the session:

```bash
# Check for new session files
find ~/.local/share/opencode -name "*.json" -mmin -5

# Watch OpenCode logs
tail -f ~/.local/share/opencode/log/*.log
```

---

## Step 6: Investigate API

OpenCode may have API endpoints for session management:

```bash
# Try common endpoints
curl -s http://localhost:4105/api/sessions 2>/dev/null | head -50
curl -s http://localhost:4105/api/session/list 2>/dev/null | head -50
curl -s http://localhost:4105/sessions 2>/dev/null | head -50

# Check OpenCode documentation/config
cat ~/.config/opencode/config.json 2>/dev/null
cat ~/.config/opencode/opencode.json 2>/dev/null
```

---

## Step 7: Check FleetDispatcher Integration

The dispatch uses `lib/fleet/backends/opencode.py`:

```bash
# Find the backend code
cat ~/agent-skills/lib/fleet/backends/opencode.py | head -100

# Check what HTTP endpoints it calls
grep -n "http" ~/agent-skills/lib/fleet/backends/opencode.py
```

---

## Expected Outcomes

After investigation, you should know:

1. **Why OpenCode isn't processing dispatches**
   - Server health issues?
   - API endpoint changes?
   - Authentication/permission issues?
   - Rate limiting?

2. **How to fix it**
   - Server restart?
   - Config update?
   - Code fix in FleetDispatcher?

3. **Proof it works**
   - Manual dispatch → commit → PR created

---

## Reporting

When done, report findings:

**Option A**: Post to Slack #fleet-events
```bash
# Using slack-mcp-server if available
~/go/bin/slack-mcp-server --transport stdio <<'EOF'
{"method":"tools/call","params":{"name":"conversations_add_message","arguments":{"channel":"C09MQGMFKDE","text":"🔧 OpenCode Investigation Report (epyc6)\n\n**Root Cause**: [describe]\n**Fix Applied**: [describe]\n**Test Result**: [pass/fail]\n**PR Created**: [URL or N/A]"}}}
EOF
```

**Option B**: Create a doc
```bash
cat > ~/agent-skills/docs/opencode-investigation-$(date +%Y%m%d).md << 'EOF'
# OpenCode Investigation - epyc6

## Date: $(date)

## Root Cause
[Your findings]

## Fix Applied
[What you did]

## Verification
[Test results]

## Recommendations
[Next steps]
EOF

cd ~/agent-skills
git add docs/
git commit -m "docs: OpenCode investigation findings"
git push
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `~/.local/share/opencode/log/*.log` | OpenCode server logs |
| `~/.config/opencode/config.json` | OpenCode configuration |
| `~/.fleet-controller/dispatches.json` | Fleet Controller state |
| `~/agent-skills/lib/fleet/backends/opencode.py` | Dispatch backend code |
| `~/agent-skills/scripts/dx-dispatch.py` | Dispatch CLI |
| `~/prime-radiant-ai/scripts/jules/nightly_dispatch.py` | Nightly dispatcher |

---

## Success Criteria

✅ OpenCode server responding to health checks
✅ Manual `opencode run` command creates commits
✅ dx-dispatch creates a new session
✅ Dispatch results in a branch with commits
✅ (Bonus) PR is created from the dispatch

Good luck! Report back with findings.
