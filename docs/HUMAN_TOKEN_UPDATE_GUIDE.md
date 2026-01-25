# Human Token Update Guide - Phase 1 & 2 Complete Summary

## Status: Ready for Token Update (After Rate Limit Reset)

---

## What Was Completed (Phase 1 + Phase 2)

### Phase 1: Infrastructure Fix (agent-skills-5f2)
- ✅ **5f2.2**: Added `RestartSec=30` rate limiting to all systemd services (prevents crash loops)
- ✅ **5f2.4**: All services restarted and verified active
- ⏳ **5f2.1**: Service account creation BLOCKED by 1Password rate limit (1000/1000 used)

### Phase 2: Auto-Checkpoint Feature (agent-skills-tis) - COMPLETE ✅
- ✅ **tis.1**: Created `~/.config/secret-cache/secrets.env` with `ZAI_API_KEY` (Tier 2)
- ✅ **tis.2**: Deployed `~/.local/bin/auto-checkpoint.sh` (pure bash, GLM fallback)
- ✅ **tis.3**: Deployed `~/.local/bin/generate-commit-msg.sh` (GLM-4.5 Flash via curl)
- ✅ **tis.4**: Cron entries deployed to all 3 VMs (staggered: :00, :05, :10)
- ✅ **tis.5**: Beads epic `agent-skills-tis` CLOSED

### Token Naming Standardization - COMPLETE ✅
All VMs now use `op-<hostname>-token` convention:
- epyc6: `op-epyc6-token`
- homedesktop-wsl: `op-homedesktop-wsl-token`
- macmini: `op-macmini-token`

### Security Fixes Applied
- ✅ Directory permissions: `chmod 700 ~/.config/systemd/user` (was 755)
- ✅ `.gitignore` protection added to all systemd user directories

---

## What's Pending

### 5f2.1: Create 3 Service Accounts (BLOCKED)

**Blocker**: 1Password Teams limit exhausted (1,000 reads/day used)
**Reset**: ~18 hours from 2026-01-24
**Options**:
1. Wait for daily reset
2. Upgrade to 1Password Business (10,000 reads/hour per token)
3. Deploy 1Password Connect Server

**Service Accounts Needed**:
| Account Name | Purpose | Target VM |
|--------------|---------|-----------|
| `opencode-cleanup` | Opencode service token rotation | All VMs |
| `auto-checkpoint-epyc6` | Auto-checkpoint GLM API access | epyc6 |
| `auto-checkpoint-macmini` | Auto-checkpoint GLM API access | macmini |

---

## Next Steps for You (Manual Token Update)

### Prerequisites
1. ⏳ Wait for 1Password rate limit to reset (~18 hours)
2. 📱 Have 1Password app open on your device

---

### Quick Method (Recommended: Using Existing Scripts)

The `agent-skills` repo has token management scripts that use the
hostname-based naming convention (`op-<hostname>-token`).

```bash
# Step 1: Create 3 service accounts EXTERNALLY in 1Password
# (Use the 1Password app or CLI on your device)
# You'll get 3 unique tokens - one for each VM

# Step 2: From ANY VM, run the distribution script:
cd ~/agent-skills/scripts
./distribute-unique-tokens.sh
# The script will prompt for each token:
# - Token for feng@epyc6 (op-epyc6-token)
# - Token for fengning@homedesktop-wsl (op-homedesktop-wsl-token)
# - Token for fengning@macmini (op-macmini-token)
# Paste each token when prompted.

# Step 3: Verify services on each VM:
systemctl --user is-active opencode.service       # should print "active"
systemctl --user is-active slack-coordinator.service  # should print "active"

# Step 4: Close epic:
cd ~/agent-skills
bd update agent-skills-5f2 --status closed
bd sync
git push
```

**What this script does:**
- `distribute-unique-tokens.sh`: Prompts for 3 unique tokens, distributes each to its VM
  - Transfers over SSH (encrypted)
  - Uses systemd-creds for host-bound encryption at rest (if available)
  - Falls back to chmod 600 plaintext if systemd-creds missing

**Alternative (run on each VM separately):**
```bash
# On epyc6:
cd ~/agent-skills/scripts && ./create-op-credential.sh --force

# On homedesktop-wsl:
ssh fengning@homedesktop-wsl
cd ~/agent-skills/scripts && ./create-op-credential.sh --force

# On macmini:
ssh fengning@macmini
cd ~/agent-skills/scripts && ./create-op-credential.sh --force
```

---

### Manual Method (If Scripts Fail)

### Step 1: Create 3 Service Accounts in 1Password

For each service account, create a new service account in 1Password:

```bash
# On ANY VM with op CLI access:
op account create --name "opencode-cleanup" --accounts-file ~/op-accounts.json
op account create --name "auto-checkpoint-epyc6" --accounts-file ~/op-accounts.json
op account create --name "auto-checkpoint-macmini" --accounts-file ~/op-accounts.json
```

Then export the tokens:
```bash
# This will show the token - SAVE EACH ONE SECURELY
op account token --account opencode-cleanup
op account token --account auto-checkpoint-epyc6
op account token --account auto-checkpoint-macmini
```

### Step 2: Update Tokens on Each VM

#### On epyc6 (local)
```bash
# 1. Update op-epyc6-token with NEW service account token
echo "YOUR_NEW_TOKEN_HERE" > ~/.config/systemd/user/op-epyc6-token
chmod 600 ~/.config/systemd/user/op-epyc6-token

# 2. Verify service files reference correct token
grep "op-epyc6-token" ~/.config/systemd/user/*.service

# 3. Restart services
systemctl --user daemon-reload
systemctl --user restart opencode.service
systemctl --user restart slack-coordinator.service

# 4. Verify active
systemctl --user is-active opencode.service   # should print "active"
systemctl --user is-active slack-coordinator.service  # should print "active"
```

#### On homedesktop-wsl
```bash
ssh fengning@homedesktop-wsl

# 1. Update op-homedesktop-wsl-token
echo "YOUR_NEW_TOKEN_HERE" > ~/.config/systemd/user/op-homedesktop-wsl-token
chmod 600 ~/.config/systemd/user/op-homedesktop-wsl-token

# 2. Verify and restart
grep "op-homedesktop-wsl-token" ~/.config/systemd/user/*.service
systemctl --user daemon-reload
systemctl --user restart opencode.service
systemctl --user restart slack-coordinator.service
systemctl --user is-active opencode.service
systemctl --user is-active slack-coordinator.service
```

#### On macmini
```bash
ssh fengning@macmini

# 1. Update op-macmini-token
echo "YOUR_NEW_TOKEN_HERE" > ~/.config/systemd/user/op-macmini-token
chmod 600 ~/.config/systemd/user/op-macmini-token

# 2. macmini uses launchd, not systemd
launchctl kickstart -k gui/$(id -u)/com.agent.opencode-server

# 3. Verify running
launchctl list | grep opencode
```

### Step 3: Verify Auto-Checkpoint Works

On each VM, test the GLM integration:
```bash
# Source the cached secrets
source ~/.config/secret-cache/secrets.env

# Test commit message generation
~/.local/bin/generate-commit-msg.sh "README.md | 1 +"
# Should output something like: [AUTO] docs: update README

# If it works, you should see a commit message starting with [AUTO]
```

### Step 4: Close the Epic

Once all tokens are updated and services verified:

```bash
cd ~/agent-skills

# Update Beads issue
bd update agent-skills-5f2 --status closed

# Sync and push
bd sync
git add -A
git commit -m "feat: complete Phase 1 infrastructure fix

- Created 3 service accounts in 1Password
- Distributed tokens to all VMs
- All services verified active

Closes agent-skills-5f2"
git push
```

---

## Security Reminders

### CRITICAL: Linux VMs Have NO Disk Encryption 🔴
- **epyc6**: LUKS not enabled (tokens stored in clear text)
- **homedesktop-wsl**: BitLocker not enabled on Windows host
- **macmini**: FileVault enabled ✅

**Consider enabling disk encryption before storing new tokens.**

### Token Safety
- Tokens are now in `~/.config/systemd/user/` with `chmod 600` permissions
- `.gitignore` protection prevents accidental git commits
- `LoadCredential` injects tokens into memory only (not disk)

---

## Quick Verification Command

Run this to verify all tokens exist:
```bash
for vm in epyc6 homedesktop-wsl macmini; do
    echo "=== $vm ==="
    ssh fengning@$vm "ls -la ~/.config/systemd/user/op-*-token 2>/dev/null || echo 'MISSING'"
done
```

---

## Related Documentation

- `docs/SERVICE_ACCOUNT_TOKEN_UPDATE_GUIDE.md` - Detailed technical guide
- `docs/TOKEN_RENAMING_SUMMARY.md` - Token naming verification
- `docs/AUTO_CHECKPOINT_IMPLEMENTATION.md` - Auto-checkpoint technical spec
- `docs/INFRA_AND_CHECKPOINT_DEV_PROMPT.md` - Full implementation plan

---

**Epic**: `agent-skills-5f2` (Infrastructure Fix)
**Status**: Phase 1 pending rate limit reset | Phase 2 complete ✅
**Updated**: 2026-01-24
