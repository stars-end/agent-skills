# One-Shot Prompt: Complete ru sync Strategy (Land the Plane)

**Engineer:** Full-stack developer
**Epic:** `agent-skills-0pf`
**Estimated Time:** 30-45 minutes

---

## Status: 80% Complete

Most tasks are **already implemented**. This prompt completes the remaining work.

| Task | Description | Status |
|------|-------------|--------|
| `0pf.4` | dx-dispatch ru sync integration | ✅ **DONE** (scripts/dx-dispatch.py:60-105) |
| `0pf.5` | start-feature ru sync integration | ✅ **DONE** (feature-lifecycle/start.sh:19-30) |
| `0pf.6` | Log rotation for ru-sync.log | ❌ **TODO** |
| `0pf.7` | Documentation | ✅ **DONE** (docs/REPO_SYNC_STRATEGY.md) |
| `0pf.8` | Verification on all VMs | ❌ **TODO** |
| `0pf.9` | Cron-based ru sync | ✅ **DONE** (all 3 VMs) |

---

## Task 0pf.6: Add Log Rotation for ru-sync.log

The auto-checkpoint.log has rotation but ru-sync.log does not.

### Deploy to all VMs

```bash
# === epyc6 ===
ssh feng@epyc6 'bash -s' << 'EOF'
# Check if rotation exists
if crontab -l 2>/dev/null | grep -q "ru-sync.*truncate"; then
  echo "✅ Log rotation already configured"
else
  # Add rotation (same pattern as auto-checkpoint)
  (crontab -l 2>/dev/null; echo "# ru-sync log rotation - truncate logs >10M daily") | crontab -
  (crontab -l 2>/dev/null; echo "0 1 * * * find ~/logs -name 'ru-sync.log' -size +10M -exec truncate -s 0 {} \;") | crontab -
  echo "✅ Log rotation added"
fi
crontab -l | grep "ru-sync"
EOF

# === homedesktop-wsl ===
ssh fengning@homedesktop-wsl 'bash -s' << 'EOF'
if crontab -l 2>/dev/null | grep -q "ru-sync.*truncate"; then
  echo "✅ Log rotation already configured"
else
  (crontab -l 2>/dev/null; echo "# ru-sync log rotation") | crontab -
  (crontab -l 2>/dev/null; echo "0 1 * * * find ~/logs -name 'ru-sync.log' -size +10M -exec truncate -s 0 {} \;") | crontab -
  echo "✅ Log rotation added"
fi
crontab -l | grep "ru-sync"
EOF

# === macmini ===
ssh fengning@macmini 'bash -s' << 'EOF'
if crontab -l 2>/dev/null | grep -q "ru-sync.*truncate"; then
  echo "✅ Log rotation already configured"
else
  (crontab -l 2>/dev/null; echo "# ru-sync log rotation") | crontab -
  (crontab -l 2>/dev/null; echo "0 1 * * * find ~/logs -name 'ru-sync.log' -size +10M -exec truncate -s 0 {} \;") | crontab -
  echo "✅ Log rotation added"
fi
crontab -l | grep "ru-sync"
EOF
```

### Verify

```bash
for vm in epyc6 homedesktop-wsl macmini; do
  echo "=== $vm ==="
  ssh "fengning@$vm" "crontab -l | grep -E 'ru-sync.*(truncate|rotation)'" 2>/dev/null || echo "Not configured"
done
```

### Close Task

```bash
bd update agent-skills-0pf.6 --status closed
```

---

## Task 0pf.8: Verification on All VMs

Run the verification checklist from `docs/REPO_SYNC_STRATEGY.md` on each VM.

### Verification Script

```bash
#!/bin/bash
# verify-ru-sync.sh - Run on each VM

echo "=== ru sync Verification ==="
echo "VM: $(hostname)"
echo ""

# 1. Cron entries exist
echo "1. Checking cron entries..."
if crontab -l 2>/dev/null | grep -qE "ru sync"; then
  echo "   ✅ ru sync cron entries found"
  crontab -l | grep "ru sync" | head -3
else
  echo "   ❌ No ru sync cron entries"
fi
echo ""

# 2. Logs directory exists
echo "2. Checking logs..."
if [[ -f ~/logs/ru-sync.log ]]; then
  echo "   ✅ Log file exists: ~/logs/ru-sync.log"
  echo "   Size: $(du -h ~/logs/ru-sync.log | cut -f1)"
  echo "   Last entry: $(tail -1 ~/logs/ru-sync.log 2>/dev/null | head -c 80)..."
else
  echo "   ⚠️  Log file not found (will be created on first run)"
  mkdir -p ~/logs
  touch ~/logs/ru-sync.log
fi
echo ""

# 3. ru binary accessible
echo "3. Checking ru binary..."
if command -v ru &>/dev/null; then
  echo "   ✅ ru found: $(which ru)"
  echo "   Version: $(ru --version 2>/dev/null || echo 'unknown')"
else
  echo "   ❌ ru not found in PATH"
fi
echo ""

# 4. Manual sync test
echo "4. Testing manual sync..."
if ru sync --non-interactive --quiet 2>&1; then
  echo "   ✅ ru sync succeeded"
else
  echo "   ⚠️  ru sync had warnings (dirty tree expected)"
fi
echo ""

# 5. Dirty tree detection
echo "5. Testing dirty tree detection..."
cd ~/agent-skills 2>/dev/null || cd ~
echo "# test-verify-$(date +%s)" >> README.md 2>/dev/null || true
if ru sync agent-skills --non-interactive 2>&1 | grep -qi "skip\|dirty\|uncommitted"; then
  echo "   ✅ Dirty tree correctly detected"
else
  echo "   ⚠️  Dirty tree detection unclear (check manually)"
fi
git checkout README.md 2>/dev/null || true
echo ""

# 6. Log rotation configured
echo "6. Checking log rotation..."
if crontab -l 2>/dev/null | grep -qE "ru-sync.*truncate"; then
  echo "   ✅ Log rotation configured"
else
  echo "   ❌ Log rotation NOT configured"
fi
echo ""

# 7. Integration with auto-checkpoint
echo "7. Checking auto-checkpoint + ru sync timing..."
AC_TIME=$(crontab -l 2>/dev/null | grep "auto-checkpoint.*agent-skills" | grep -oE "^[0-9]+" | head -1)
RU_TIME=$(crontab -l 2>/dev/null | grep "ru sync.*agent-skills" | grep -oE "^[0-9]+" | head -1)
if [[ -n "$AC_TIME" && -n "$RU_TIME" ]]; then
  DIFF=$((RU_TIME - AC_TIME))
  if [[ $DIFF -ge 3 && $DIFF -le 10 ]]; then
    echo "   ✅ Timing correct: auto-checkpoint at :$AC_TIME, ru sync at :$RU_TIME (${DIFF}min gap)"
  else
    echo "   ⚠️  Timing may need adjustment: auto-checkpoint at :$AC_TIME, ru sync at :$RU_TIME"
  fi
else
  echo "   ⚠️  Could not determine timing (check crontab manually)"
fi
echo ""

echo "=== Verification Complete ==="
```

### Run on All VMs

```bash
# Save script locally
cat > /tmp/verify-ru-sync.sh << 'SCRIPT_EOF'
# (paste the script above)
SCRIPT_EOF
chmod +x /tmp/verify-ru-sync.sh

# Run on each VM
for vm in epyc6 homedesktop-wsl macmini; do
  echo ""
  echo "########################################"
  echo "# Verifying $vm"
  echo "########################################"
  ssh "fengning@$vm" 'bash -s' < /tmp/verify-ru-sync.sh
done
```

### Expected Results

| VM | Cron | Logs | ru | Sync | Dirty | Rotation | Timing |
|----|------|------|-----|------|-------|----------|--------|
| epyc6 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | :05→:10 |
| homedesktop-wsl | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | :00→:05 |
| macmini | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | :05→:10 |

### Close Task

```bash
bd update agent-skills-0pf.8 --status closed
```

---

## Close Remaining Tasks (Already Done)

These tasks are already implemented. Close them:

```bash
# dx-dispatch integration (already in dx-dispatch.py)
bd update agent-skills-0pf.4 --status closed

# start-feature integration (already in start.sh)
bd update agent-skills-0pf.5 --status closed

# Documentation (already in docs/REPO_SYNC_STRATEGY.md)
bd update agent-skills-0pf.7 --status closed

# Cron setup (already on all VMs)
bd update agent-skills-0pf.9 --status closed
```

---

## Close Epic

After all tasks are closed:

```bash
# Verify all tasks closed
bd show agent-skills-0pf

# Close epic
bd update agent-skills-0pf --status closed

# Sync and push
bd sync
git add -A
git commit -m "chore(beads): close agent-skills-0pf epic (ru sync strategy complete)

All tasks completed:
- ✅ dx-dispatch syncs before dispatch
- ✅ start-feature syncs before branching
- ✅ Cron-based sync on all 3 VMs
- ✅ Log rotation configured
- ✅ Documentation complete
- ✅ Verification passed

Feature-Key: agent-skills-0pf"
git push
```

---

## Final State

After completion:

```
ru sync Strategy - COMPLETE ✅

┌─────────────────────────────────────────────────────────────┐
│                    SYNC ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  SCHEDULED (cron):                                          │
│  ├── Every 4h: auto-checkpoint → ru sync (agent-skills)    │
│  └── Daily 12:00 UTC: auto-checkpoint → ru sync (all)      │
│                                                             │
│  EVENT-DRIVEN:                                              │
│  ├── dx-dispatch: syncs before dispatching                 │
│  └── start-feature: syncs before branching                 │
│                                                             │
│  SAFETY:                                                    │
│  ├── Dirty tree detection (auto-checkpoint commits first)  │
│  ├── Auto-checkpoint runs 5min before ru sync              │
│  └── Log rotation prevents disk fill                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Timing (per VM stagger):
  homedesktop-wsl: checkpoint :00 → sync :05
  macmini:         checkpoint :05 → sync :10
  epyc6:           checkpoint :10 → sync :15
```

---

## Checklist

- [ ] Log rotation added to all 3 VMs
- [ ] Verification passed on all 3 VMs
- [ ] Tasks 0pf.4, 0pf.5, 0pf.6, 0pf.7, 0pf.8, 0pf.9 closed
- [ ] Epic agent-skills-0pf closed
- [ ] Changes pushed to git

---

**Document:** `docs/RU_SYNC_COMPLETION_PROMPT.md`
**Last Updated:** 2026-01-24
# ARCHIVE / HISTORICAL
#
# This is a historical completion prompt for ru sync setup. Commands may need
# adjustment based on current canonical targets. For current usage, prefer:
# - docs/CANONICAL_TARGETS.md
# - docs/REPO_SYNC_STRATEGY.md
