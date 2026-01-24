# Token Renaming and Security Fixes Summary

**Date**: 2026-01-24
**Status**: ✅ Complete

## Overview

Applied consistent token naming convention (`op-<hostname>-token`) and security fixes across all 3 canonical VMs.

## Token Naming Convention

| VM | Old Name | New Name |
|-----|----------|----------|
| epyc6 | `op_token` | `op-epyc6-token` |
| homedesktop-wsl | `op_token` | `op-homedesktop-wsl-token` |
| macmini | `op_token` | `op-macmini-token` |

## Security Fixes Applied

### 1. Directory Permissions
Changed systemd user directory from `drwxrwxr-x` (755) to `drwx------` (700):
- ✅ epyc6
- ✅ homedesktop-wsl
- ✅ macmini

### 2. .gitignore Protection
Added `.gitignore` with deny-all pattern to `~/.config/systemd/user/`:
```
*
!.gitignore
```
- ✅ epyc6
- ✅ homedesktop-wsl
- ✅ macmini

### 3. Service Files Updated

#### epyc6
- `~/.config/systemd/user/opencode.service`
- `~/.config/systemd/user/slack-coordinator.service`

#### homedesktop-wsl
- `~/.config/systemd/user/opencode.service`
- `~/.config/systemd/user/slack-coordinator.service`

#### macmini
- No LoadCredential usage (uses launchd, not systemd)
- Token renamed for consistency only

## Verification Results

### epyc6
```bash
$ ls -la ~/.config/systemd/user/op-epyc6-token
-rw------- 1 feng feng 852 Jan 20 20:32 op-epyc6-token

$ systemctl --user is-active opencode.service
active ✓

$ systemctl --user is-active slack-coordinator.service
active ✓
```

### homedesktop-wsl
```bash
$ ls -la ~/.config/systemd/user/op-homedesktop-wsl-token
-rw------- 1 fengning fengning 852 Jan 20 20:32 op-homedesktop-wsl-token

$ systemctl --user is-active opencode.service
active ✓

$ systemctl --user is-active slack-coordinator.service
active ✓
```

### macmini
```bash
$ ls -la ~/.config/systemd/user/op-macmini-token
-rw-------  1 fengning  staff  852 Jan 22 05:47 op-macmini-token

$ launchctl list | grep opencode
32142	0	com.agent.opencode-server ✓
```

## Remaining Work

### 5f2.1: Create 3 Service Accounts (BLOCKED)
- **Status**: 1Password rate limit exhausted (1000/1000 daily)
- **Wait**: ~18 hours for daily reset OR upgrade to Business tier
- **Action**: Create `opencode-cleanup`, `auto-checkpoint-epyc6`, `auto-checkpoint-macmini`
- **Guide**: See `SERVICE_ACCOUNT_TOKEN_UPDATE_GUIDE.md`

### CRITICAL: Disk Encryption
- 🔴 **epyc6**: No disk encryption (LUKS not enabled)
- 🔴 **homedesktop-wsl**: No disk encryption (BitLocker not enabled on Windows host)
- ✅ **macmini**: FileVault enabled

## Commands to Verify Token Naming

```bash
# Check all tokens in one command
for vm in epyc6 homedesktop-wsl macmini; do
    echo "=== $vm ==="
    ssh fengning@$vm "ls -la ~/.config/systemd/user/op-*-token 2>/dev/null || echo 'Token not found'"
done
```

## Next Steps

1. Wait for 1Password rate limit reset (~18 hours from 2026-01-24)
2. Follow `SERVICE_ACCOUNT_TOKEN_UPDATE_GUIDE.md` to create and distribute new service account tokens
3. Consider enabling disk encryption on Linux VMs (CRITICAL security issue)

---

**Reference**: agent-skills-5f2 epic (Infrastructure Fix)
