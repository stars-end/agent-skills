# Cross-VM Verification Matrix (V8.4)

**Last Updated:** 2026-02-27
**Authoritative Source:** `configs/fleet_hosts.yaml`

This document provides a deterministic verification matrix for all canonical VMs, including authentication principals, tool presence, token paths, and cc-glm-headless resolution states.

---

## 1. Canonical VM Registry

| Host | OS | SSH Principal | User | Notes |
|------|-----|---------------|------|-------|
| homedesktop-wsl | Linux (WSL2) | `fengning@homedesktop-wsl` | fengning | Primary dev environment |
| macmini | macOS | `fengning@macmini` | fengning | Captain VM - heartbeat origin |
| epyc6 | Linux | `fengning@epyc6` | fengning | GPU/ML work |
| epyc12 | Linux | `fengning@epyc12` | fengning | Secondary Linux host |

**All canonical VMs now use `fengning@` username consistently.**

---

## 2. Verification Matrix

### 2.1 Authentication & Access

| Check | homedesktop-wsl | macmini | epyc6 | epyc12 |
|-------|-----------------|---------|-------|--------|
| SSH reachable (direct) | N/A (local) | ✅ | ✅ | ✅ |
| SSH reachable (via jump) | - | - | - | - |
| Tailscale SSH | ✅ | ✅ | ✅ | ✅ |
| Auth principal verified | `fengning` | `fengning` | `fengning` | `fengning` |
| Last check | 2026-02-27 | 2026-02-27 | 2026-02-27 | 2026-02-27 |

### 2.2 Tool Presence

| Tool | homedesktop-wsl | macmini | epyc6 | epyc12 |
|------|-----------------|---------|-------|--------|
| `jq` | ✅ | ✅ | ❌ (no sudo) | ✅ |
| `curl` | ✅ | ✅ | ✅ | ✅ |
| `git` | ✅ | ✅ | ✅ | ✅ |
| `bd` (beads) | ✅ | ✅ | ✅ | ✅ |
| `ru` (repo_updater) | ✅ | ✅ | ✅ | ✅ |
| `op` CLI (1Password) | ✅ | ✅ | ❌ | ✅ |
| `claude` CLI | ✅ | ✅ | ✅ | ✅ |
| `mise` | ✅ | ✅ | ✅ | ✅ |
| `dcg` | ✅ | ✅ | ✅ | ✅ |

**Note:** epyc6 lacks `op` CLI. epyc12 has `op` installed; validate token/session before production waves.

### 2.3 1Password Token Paths

| VM | Token File Path | Status |
|----|-----------------|--------|
| homedesktop-wsl | `~/.config/systemd/user/op-homedesktop-wsl-token` | ✅ Active |
| macmini | `~/.config/systemd/user/op-macmini-token` | ✅ Active (legacy) |
| epyc6 | N/A | ❌ No op CLI |
| epyc12 | `~/.config/systemd/user/op-epyc12-token` | ✅ Token file present |

**Legacy Note:** macmini uses a hardcoded legacy path `op-macmini-token` in `cc-glm-headless.sh` for backward compatibility.

### 2.4 cc-glm-headless Resolution State

| VM | Resolution Path | Status | Notes |
|----|-----------------|--------|-------|
| homedesktop-wsl | Primary | ✅ Working | Uses `op-homedesktop-wsl-token` |
| macmini | Primary (with fallback) | ✅ Working | Falls back to `op-macmini-token` legacy path |
| epyc6 | Env-only | ⚠️ Requires setup | Must set `CC_GLM_AUTH_TOKEN` or `ZAI_API_KEY` env var |
| epyc12 | Env-only | ⚠️ Requires setup | Must set `CC_GLM_AUTH_TOKEN` or `ZAI_API_KEY` env var |

**Resolution Precedence (from `cc-glm-headless.sh`):**
1. `CC_GLM_AUTH_TOKEN` (plain token)
2. `ZAI_API_KEY` (plain token or `op://` reference)
3. `CC_GLM_OP_URI` (`op://` reference)
4. Default: `op://dev/Agent-Secrets-Production/ZAI_API_KEY`

---

## 3. SSH Connectivity Matrix

### 3.1 Direct SSH Reachability

| From → To | homedesktop-wsl | macmini | epyc6 | epyc12 |
|-----------|-----------------|---------|-------|--------|
| **homedesktop-wsl** | - | ✅ | ✅ | ✅ |
| **macmini** | ✅ | - | ✅ | ✅ |
| **epyc6** | ✅ | ✅ | - | ✅ |
| **epyc12** | ✅ | ✅ | ✅ | - |
| **VPS/cloud** | ✅ | ✅ | ✅ | ✅ |

### 3.2 Jump Host Pattern

All canonical VMs are now directly reachable via Tailscale SSH:

```bash
# Direct access to all VMs
ssh fengning@epyc6 "command"
ssh fengning@epyc12 "command"
ssh fengning@homedesktop-wsl "command"
ssh fengning@macmini "command"
```

### 3.3 Tailscale SSH (V8.3 Standard)

All canonical VMs support Tailscale SSH:

```bash
# Preferred method
tailscale ssh fengning@macmini "command"

# Direct Tailscale IP (if hostname resolution fails)
ssh fengning@100.117.177.18 "command"
```

**Deprecated:** SSH keys for canonical VM access (use Tailscale instead).

---

## 4. Macmini Access Closeout

### 4.1 Issue Summary

The macmini access path had a verification gap related to:
1. SSH principal mismatch between expected `fengning@macmini` and potential alternative configurations
2. Legacy token file path (`op-macmini-token`) requiring explicit handling
3. cc-glm-headless resolution needing a fallback for the legacy path

### 4.2 Resolution

**Status:** ✅ CLOSED

**Fix Applied:**
- `cc-glm-headless.sh` (lines 103-112) now includes explicit fallback to `op-macmini-token`:
  ```bash
  legacy_file="$HOME/.config/systemd/user/op-macmini-token"
  if [[ -f "$token_file" ]]; then
    OP_SERVICE_ACCOUNT_TOKEN="$(cat "$token_file" 2>/dev/null || true)"
    export OP_SERVICE_ACCOUNT_TOKEN
  elif [[ -f "$legacy_file" ]]; then
    OP_SERVICE_ACCOUNT_TOKEN="$(cat "$legacy_file" 2>/dev/null || true)"
    export OP_SERVICE_ACCOUNT_TOKEN
  fi
  ```

### 4.3 Fallback Procedure (SSH Principal Mismatch)

If SSH to macmini fails with principal mismatch:

```bash
# 1. Verify Tailscale is active
tailscale status | grep -i mac

# 2. Try Tailscale SSH directly
tailscale ssh fengning@macmini "echo OK"

# 3. If hostname fails, use Tailscale IP
# Get IP from: tailscale status
ssh fengning@100.117.177.18 "echo OK"

# 4. If still failing, verify SSH config
cat ~/.ssh/config | grep -A5 -i macmini

# 5. Emergency: Use bonjour hostname
ssh fengning@Fengs-Mac-mini-3.local "echo OK"
```

### 4.4 Verification Commands

```bash
# From any VM, verify macmini access:
ssh -o ConnectTimeout=5 fengning@macmini "echo OK" && echo "Direct SSH: OK"
tailscale ssh fengning@macmini "echo OK" && echo "Tailscale SSH: OK"

# Verify op CLI token on macmini:
ssh fengning@macmini "cat ~/.config/systemd/user/op-macmini-token 2>/dev/null | head -c 10 && echo '...'" || echo "Token missing"

# Verify cc-glm-headless works on macmini:
ssh fengning@macmini "source ~/.zshrc && which cc-glm-headless.sh"
```

---

## 5. Alignment with Fleet Configuration

### 5.1 fleet_hosts.yaml Consistency

| Field | This Document | fleet_hosts.yaml | Match |
|-------|---------------|------------------|-------|
| macmini.ssh | `fengning@macmini` | `fengning@Fengs-Mac-mini-3.local` | ⚠️ Different format |
| macmini.user | fengning | fengning | ✅ |
| epyc6.ssh | `fengning@epyc6` | `fengning@epyc6` | ✅ |
| epyc6.user | fengning | fengning | ✅ |
| epyc12.ssh | `fengning@epyc12` | `fengning@epyc12` | ✅ |
| epyc12.user | fengning | fengning | ✅ |
| homedesktop-wsl.ssh | `fengning@homedesktop-wsl` | `fengning@homedesktop-wsl` | ✅ |

**Note:** macmini hostname variation (`macmini` vs `Fengs-Mac-mini-3.local`) is acceptable - both resolve correctly via Tailscale or mDNS.

### 5.2 canonical-targets.sh Consistency

All VMs in this matrix match `scripts/canonical-targets.sh`:
- `CANONICAL_VMS` array
- `CANONICAL_VM_*` environment variables

---

## 6. Operational Verification Checklist

### Pre-Deployment Check

Before deploying cc-glm-headless dependent workloads:

```bash
# 1. Verify target VM access
for vm in "fengning@homedesktop-wsl" "fengning@macmini" "fengning@epyc6" "fengning@epyc12"; do
  timeout 5 ssh "$vm" "echo OK" && echo "✅ $vm" || echo "❌ $vm"
done

# 2. Verify op CLI (for op:// resolution)
for vm in "fengning@homedesktop-wsl" "fengning@macmini"; do
  ssh "$vm" "command -v op >/dev/null && echo '✅ op CLI' || echo '❌ no op'"
done

# 3. Verify token files
for vm in "fengning@homedesktop-wsl" "fengning@macmini"; do
  host=$(ssh "$vm" "hostname")
  ssh "$vm" "test -f ~/.config/systemd/user/op-${host}-token && echo '✅ token' || echo '❌ no token'"
done

# 4. Test cc-glm-headless resolution
~/agent-skills/extended/cc-glm/scripts/cc-glm-headless.sh --prompt "echo test" 2>&1 | head -5
```

---

## 7. Related Documentation

- `configs/fleet_hosts.yaml` - Authoritative fleet configuration
- `scripts/canonical-targets.sh` - Environment variables for VMs/IDEs
- `docs/CANONICAL_TARGETS.md` - Canonical targets registry
- `docs/SECRETS_INDEX.md` - Secret management reference
- `extended/cc-glm/SKILL.md` - cc-glm delegation patterns
- `extended/cc-glm/scripts/cc-glm-headless.sh` - Headless execution script

---

## 8. Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-02-27 | V8.4: Host-identity convergence - epyc6 now uses `fengning@` | bd-zgzw |
| 2026-02-27 | Updated Tailscale IPs, direct SSH for all VMs | bd-zgzw |
| 2026-02-18 | Initial creation with full verification matrix | bd-xga8.10.6 |
| 2026-02-18 | Added macmini access closeout section | bd-xga8.10.6 |
| 2026-02-18 | Added epyc12 to matrix | bd-xga8.10.6 |
