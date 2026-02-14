---
name: fleet-deploy
description: |
  Deploy changes across canonical VMs (macmini, homedesktop-wsl, epyc6, epyc12).
  MUST BE USED when deploying scripts, crontabs, or config changes to multiple VMs.
  Uses configs/fleet_hosts.yaml as authoritative source for SSH targets and users.
tags: [fleet, deploy, vm, canonical, dx-dispatch, ssh, infrastructure]
allowed-tools:
  - Read
  - Bash(ssh:*)
  - Bash(scp:*)
  - Bash(git:*)
---

# Fleet Deploy

Deploy changes across all canonical VMs from a single source of truth.

## Purpose

Standardize fleet-wide deployment using `configs/fleet_hosts.yaml` as the authoritative
registry. Eliminates hardcoded SSH targets and user confusion (e.g., `feng@epyc6` vs `fengning@macmini`).

## When to Use This Skill

**Trigger phrases:**
- "deploy to all VMs"
- "fleet deploy"
- "push to canonical VMs"
- "roll out to fleet"
- "run on all machines"

**Use when:**
- Deploying new scripts to ~/agent-skills/scripts/
- Adding/updating crontabs across VMs
- Rolling out config changes
- Running git pull across fleet
- Verifying deployment status

## Canonical VM Registry

**Source of truth:** `~/agent-skills/configs/fleet_hosts.yaml`

| VM | User | SSH | OS | Use Case |
|----|------|-----|-----|----------|
| macmini | fengning | fengning@macmini | macos | Captain, macOS builds |
| homedesktop-wsl | fengning | fengning@homedesktop-wsl | linux | Primary dev, DCG |
| epyc6 | feng | feng@epyc6 | linux | GPU, ML training |
| epyc12 | fengning | fengning@epyc12 | linux | Secondary Linux |

**Note:** epyc6 uses `feng@` while others use `fengning@` - always check the YAML.

## Workflow

### 1. Discover Fleet

```bash
# List all canonical VMs with users
python3 - "$HOME/agent-skills/configs/fleet_hosts.yaml" <<'PY'
import yaml, sys
hosts = yaml.safe_load(open(sys.argv[1]))['hosts']
for name, h in sorted(hosts.items()):
    print(f"{name}: {h['user']}@{name} ({h['os']})")
PY
```

### 2. Deploy Script/Config

**Option A: Git pull (preferred for agent-skills changes)**
```bash
for vm in macmini homedesktop-wsl epyc6; do
  user=$(python3 - - <<< "import yaml; h=yaml.safe_load(open('$HOME/agent-skills/configs/fleet_hosts.yaml'))['hosts']; print(h['$vm']['user'])")
  echo "=== $vm ($user) ==="
  ssh "$user@$vm" 'cd ~/agent-skills && git pull'
done
```

**Option B: dx-dispatch (for complex operations)**
```bash
dx-dispatch epyc6 "cd ~/agent-skills && git pull && make install"
dx-dispatch homedesktop-wsl "cd ~/agent-skills && git pull"
dx-dispatch macmini "cd ~/agent-skills && git pull"
```

**Option C: scp (for one-off files)**
```bash
# Get user from YAML
user=$(grep -A5 "epyc6:" ~/agent-skills/configs/fleet_hosts.yaml | grep "user:" | awk '{print $2}')
scp ~/agent-skills/scripts/new-script.sh "$user@epyc6:~/agent-skills/scripts/"
```

### 3. Add Crontab Entry

```bash
# Template for adding cron to all VMs
for vm in macmini homedesktop-wsl epyc6; do
  user=$(python3 - - <<< "import yaml; h=yaml.safe_load(open('$HOME/agent-skills/configs/fleet_hosts.yaml'))['hosts']; print(h['$vm']['user'])")

  ssh "$user@$vm" 'bash -s' << 'SCRIPT'
if ! crontab -l 2>/dev/null | grep -q "my-new-cron-job"; then
  (crontab -l 2>/dev/null; echo '
# My new cron job
*/15 * * * * ~/agent-skills/scripts/my-script.sh >> ~/logs/dx/my-script.log 2>&1') | crontab -
  echo "Cron added to $(hostname)"
else
  echo "Cron already exists on $(hostname)"
fi
SCRIPT
done
```

### 4. Verify Deployment

```bash
# Check script exists on all VMs
for vm in macmini homedesktop-wsl epyc6; do
  user=$(python3 - - <<< "import yaml; h=yaml.safe_load(open('$HOME/agent-skills/configs/fleet_hosts.yaml'))['hosts']; print(h['$vm']['user'])")
  echo -n "$vm: "
  ssh "$user@$vm" 'ls -la ~/agent-skills/scripts/my-script.sh 2>/dev/null && echo "OK" || echo "MISSING"'
done
```

## Quick Reference Commands

### Get SSH target for a VM
```bash
# One-liner to get user@host
python3 - - <<< "import yaml; h=yaml.safe_load(open('$HOME/agent-skills/configs/fleet_hosts.yaml'))['hosts']; v=h['epyc6']; print(f\"{v['user']}@{v['ssh'].split('@')[1]}\")"
# Output: feng@epyc6
```

### Run command on all VMs
```bash
# Using fleet_hosts.yaml
python3 - "$HOME/agent-skills/configs/fleet_hosts.yaml" <<'PY'
import yaml, subprocess, sys
hosts = yaml.safe_load(open(sys.argv[1]))['hosts']
for name, h in sorted(hosts.items()):
    target = h['ssh']
    print(f"=== {name} ({target}) ===")
    subprocess.run(['ssh', target, 'hostname && date'])
PY
```

### Parallel deploy with dx-dispatch
```bash
# Dispatch to multiple VMs in parallel
dx-dispatch epyc6 "cd ~/agent-skills && git pull" &
dx-dispatch homedesktop-wsl "cd ~/agent-skills && git pull" &
dx-dispatch macmini "cd ~/agent-skills && git pull" &
wait
echo "All VMs updated"
```

## Integration Points

### With canonical-targets.sh
```bash
source ~/agent-skills/scripts/canonical-targets.sh
echo "${CANONICAL_VMS[@]}"
# Output: feng@epyc6:linux:... fengning@macmini:macos:...
```

### With dx-dispatch
```bash
dx-dispatch --list  # Shows available VMs
dx-dispatch epyc6 "command"  # Dispatch to specific VM
```

### With multi-agent-dispatch skill
See `~/agent-skills/dispatch/multi-agent-dispatch/SKILL.md` for full dx-dispatch capabilities.

## Best Practices

### Do
- Always use `configs/fleet_hosts.yaml` for user/host lookups
- Test on one VM before fleet-wide rollout
- Use git pull for agent-skills changes (ensures version control)
- Verify deployment with ls/cat commands
- Include CRON_TZ for time-sensitive crons

### Don't
- Hardcode SSH targets (usernames differ across VMs)
- Skip epyc6 (it uses `feng@` not `fengning@`)
- Deploy without verification
- Forget to commit changes first

## What This Skill Does

- Provides single source of truth for VM SSH targets
- Standardizes deployment workflow across fleet
- Handles user differences (feng vs fengning)
- Supports git, scp, and dx-dispatch patterns
- Includes verification commands

## What This Skill DOESN'T Do

- Auto-deploy without user confirmation
- Handle non-canonical VMs
- Manage secrets or credentials
- Replace CI/CD for production deployments

## Examples

### Example 1: Deploy new script to all VMs
```bash
# 1. Commit the script first
cd ~/agent-skills
git add scripts/canonical-evacuate-active.sh
git commit -m "feat: add canonical enforcer script"
git push

# 2. Deploy to all VMs
for vm in macmini homedesktop-wsl epyc6; do
  user=$(python3 - - <<< "import yaml; h=yaml.safe_load(open('configs/fleet_hosts.yaml'))['hosts']; print(h['$vm']['user'])")
  ssh "$user@$vm" 'cd ~/agent-skills && git pull && chmod +x scripts/canonical-evacuate-active.sh'
done

# 3. Verify
for vm in macmini homedesktop-wsl epyc6; do
  user=$(python3 - - <<< "import yaml; h=yaml.safe_load(open('configs/fleet_hosts.yaml'))['hosts']; print(h['$vm']['user'])")
  ssh "$user@$vm" 'ls -la ~/agent-skills/scripts/canonical-evacuate-active.sh'
done
```

### Example 2: Add cron to all VMs with CRON_TZ
```bash
for vm in macmini homedesktop-wsl epyc6; do
  user=$(python3 - - <<< "import yaml; h=yaml.safe_load(open('configs/fleet_hosts.yaml'))['hosts']; print(h['$vm']['user'])")

  ssh "$user@$vm" 'bash -s' << 'SCRIPT'
if ! crontab -l 2>/dev/null | grep -q "canonical-evacuate"; then
  (crontab -l 2>/dev/null; echo '
CRON_TZ=America/Los_Angeles
*/15 5-16 * * * ~/agent-skills/scripts/dx-job-wrapper.sh canonical-evacuate -- ~/agent-skills/scripts/canonical-evacuate-active.sh >> ~/logs/dx/canonical-evacuate.log 2>&1') | crontab -
fi
SCRIPT
done
```

### Example 3: Quick VM status check
```bash
python3 - "$HOME/agent-skills/configs/fleet_hosts.yaml" <<'PY'
import yaml, subprocess, sys
hosts = yaml.safe_load(open(sys.argv[1]))['hosts']
for name, h in sorted(hosts.items()):
    result = subprocess.run(['ssh', '-o', 'ConnectTimeout=5', h['ssh'], 'hostname; uptime'],
                          capture_output=True, text=True, timeout=10)
    status = "OK" if result.returncode == 0 else "FAIL"
    print(f"{name}: {status}")
PY
```

## Related Skills

- **multi-agent-dispatch**: Full dx-dispatch capabilities for async/parallel dispatch
- **canonical-targets**: Shell exports for CANONICAL_VMS array
- **vm-bootstrap**: Setting up new VMs with required tooling

## Resources

- `~/agent-skills/configs/fleet_hosts.yaml` - Authoritative fleet registry
- `~/agent-skills/scripts/canonical-targets.sh` - Shell exports
- `~/agent-skills/docs/CANONICAL_TARGETS.md` - Human-readable docs

---

**Last Updated:** 2026-02-14
**Skill Type:** Workflow / Infrastructure
**Average Duration:** 2-5 minutes
