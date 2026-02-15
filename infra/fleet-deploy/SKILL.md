---
name: fleet-deploy
description: |
  Deploy changes across canonical VMs (macmini, homedesktop-wsl, epyc6, epyc12).
  MUST BE USED when deploying scripts, crontabs, or config changes to multiple VMs.
  Uses configs/fleet_hosts.yaml as authoritative source for SSH targets.
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
registry. Eliminates hardcoded SSH targets and user confusion (e.g., `feng@epyc6` vs `fengning@Fengs-Mac-mini-3.local`).

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

| VM | SSH Target | OS | Use Case |
|----|------------|-----|----------|
| macmini | fengning@Fengs-Mac-mini-3.local | macos | Captain, macOS builds |
| homedesktop-wsl | fengning@homedesktop-wsl | linux | Primary dev, DCG |
| epyc6 | feng@epyc6 | linux | GPU, ML training |
| epyc12 | fengning@epyc12 | linux | Secondary Linux |

**Note:** Always use `hosts[vm].ssh` from YAML - never reconstruct `user@vm`.

## Workflow

### 1. Discover Fleet (No PyYAML Dependency)

**Method A: Using canonical-targets.sh (recommended)**
```bash
source ~/agent-skills/scripts/canonical-targets.sh
for entry in "${CANONICAL_VMS[@]}"; do
  ssh_target="${entry%%:*}"  # Extract user@host
  echo "=== $ssh_target ==="
  ssh "$ssh_target" 'hostname'
done
```

**Method B: Using fleet_hosts.yaml with Python**
```bash
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, sys, os
yaml_path = os.path.expanduser(sys.argv[1]) if sys.argv[1].startswith('~') else sys.argv[1]
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name, h in sorted(hosts.items()):
    print(f"{name}: {h['ssh']} ({h['os']})")
PY
```

### 2. Deploy Script/Config

**Option A: Git pull (preferred for agent-skills changes)**
```bash
# Using YAML for SSH targets
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1]) if sys.argv[1].startswith('~') else sys.argv[1]
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name in ['macmini', 'homedesktop-wsl', 'epyc6']:
    h = hosts[name]
    print(f"=== {name} ({h['ssh']}) ===")
    subprocess.run(['ssh', h['ssh'], 'cd ~/agent-skills && git pull'])
PY
```

**Option B: dx-dispatch (for complex operations)**
```bash
dx-dispatch epyc6 "cd ~/agent-skills && git pull && make install"
dx-dispatch homedesktop-wsl "cd ~/agent-skills && git pull"
dx-dispatch macmini "cd ~/agent-skills && git pull"
```

**Option C: scp (for one-off files)**
```bash
# Get SSH target from YAML
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
h = yaml.safe_load(open(yaml_path))['hosts']['epyc6']
subprocess.run(['scp', '~/agent-skills/scripts/new-script.sh', f"{h['ssh']}:~/agent-skills/scripts/"])
PY
```

### 3. Add Crontab Entry

```bash
# Template for adding cron to all VMs using YAML
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name in ['macmini', 'homedesktop-wsl', 'epyc6']:
    ssh_target = hosts[name]['ssh']
    subprocess.run(['ssh', ssh_target, 'bash -s'], input='''
if ! crontab -l 2>/dev/null | grep -q "my-new-cron-job"; then
  (crontab -l 2>/dev/null; echo '
# My new cron job
*/15 * * * * ~/agent-skills/scripts/my-script.sh >> ~/logs/dx/my-script.log 2>&1') | crontab -
  echo "Cron added to $(hostname)"
else
  echo "Cron already exists on $(hostname)"
fi
''', text=True)
PY
```

### 4. Verify Deployment

```bash
# Check script exists on all VMs
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name in ['macmini', 'homedesktop-wsl', 'epyc6']:
    ssh_target = hosts[name]['ssh']
    result = subprocess.run(['ssh', ssh_target, 'ls ~/agent-skills/scripts/my-script.sh 2>/dev/null && echo OK || echo MISSING'],
                          capture_output=True, text=True)
    print(f"{name}: {result.stdout.strip()}")
PY
```

## Quick Reference Commands

### Get SSH target for a single VM
```bash
# Using canonical-targets.sh (no PyYAML)
source ~/agent-skills/scripts/canonical-targets.sh
echo "${CANONICAL_VM_PRIMARY}"   # feng@epyc6
echo "${CANONICAL_VM_MACOS}"     # fengning@macmini
```

### Run command on all VMs
```bash
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name, h in sorted(hosts.items()):
    ssh_target = h['ssh']
    print(f"=== {name} ({ssh_target}) ===")
    subprocess.run(['ssh', ssh_target, 'hostname && date'])
PY
```

### Parallel deploy with dx-dispatch
```bash
dx-dispatch epyc6 "cd ~/agent-skills && git pull" &
dx-dispatch homedesktop-wsl "cd ~/agent-skills && git pull" &
dx-dispatch macmini "cd ~/agent-skills && git pull" &
wait
echo "All VMs updated"
```

## Integration Points

### With canonical-targets.sh (No PyYAML Required)
```bash
source ~/agent-skills/scripts/canonical-targets.sh
echo "${CANONICAL_VMS[@]}"
# Output: feng@epyc6:linux:... fengning@macmini:macos:...

# Deploy to all VMs
for entry in "${CANONICAL_VMS[@]}"; do
  ssh_target="${entry%%:*}"
  ssh "$ssh_target" 'cd ~/agent-skills && git pull'
done
```

### With dx-dispatch
```bash
dx-dispatch --list  # Shows available VMs
dx-dispatch epyc6 "command"  # Dispatch to specific VM
```

## Best Practices

### Do
- Always use `hosts[vm].ssh` from YAML - never reconstruct `user@vm`
- Use `os.path.expanduser()` when YAML path starts with `~`
- Pass YAML path via `sys.argv[1]` to Python, not embedded strings
- Test on one VM before fleet-wide rollout
- Include CRON_TZ for time-sensitive crons

### Don't
- Reconstruct SSH targets as `"$user@$vm"` - use `h['ssh']` from YAML
- Embed `$HOME` inside Python heredocs (won't expand)
- Use grep|awk to parse YAML (brittle)
- Skip the `0 17 * * *` final pass for canonical-evacuate

## Examples

### Example 1: Deploy new script to all VMs
```bash
# 1. Commit the script first
cd ~/agent-skills
git add scripts/canonical-evacuate-active.sh
git commit -m "feat: add canonical enforcer script"
git push

# 2. Deploy to all VMs using YAML
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name in ['macmini', 'homedesktop-wsl', 'epyc6']:
    ssh_target = hosts[name]['ssh']
    print(f"Deploying to {name}...")
    subprocess.run(['ssh', ssh_target, 'cd ~/agent-skills && git pull && chmod +x scripts/canonical-evacuate-active.sh'])
PY

# 3. Verify
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name in ['macmini', 'homedesktop-wsl', 'epyc6']:
    result = subprocess.run(['ssh', hosts[name]['ssh'], 'ls -la ~/agent-skills/scripts/canonical-evacuate-active.sh'],
                          capture_output=True, text=True)
    print(f"{name}: {'OK' if result.returncode == 0 else 'MISSING'}")
PY
```

### Example 2: Add canonical-evacuate cron to all VMs (COMPLETE)
```bash
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name in ['macmini', 'homedesktop-wsl', 'epyc6']:
    ssh_target = hosts[name]['ssh']
    subprocess.run(['ssh', ssh_target, 'bash -s'], input='''
if ! crontab -l 2>/dev/null | grep -q "canonical-evacuate-active"; then
  (crontab -l 2>/dev/null; echo '
# CRON_TZ for canonical-evacuate (ensures 5am-5pm PT regardless of system TZ)
CRON_TZ=America/Los_Angeles
# V8.3.x: Canonical Enforcer - Active Hours (5am-5pm PT)
*/15 5-16 * * * ~/agent-skills/scripts/dx-job-wrapper.sh canonical-evacuate -- ~/agent-skills/scripts/canonical-evacuate-active.sh >> ~/logs/dx/canonical-evacuate.log 2>&1
# Final pass at 5pm PT
0 17 * * * ~/agent-skills/scripts/dx-job-wrapper.sh canonical-evacuate -- ~/agent-skills/scripts/canonical-evacuate-active.sh >> ~/logs/dx/canonical-evacuate.log 2>&1') | crontab -
  echo "Cron added to $(hostname)"
fi
''', text=True)
PY
```

### Example 3: Quick VM status check
```bash
python3 - ~/agent-skills/configs/fleet_hosts.yaml <<'PY'
import yaml, subprocess, sys, os
yaml_path = os.path.expanduser(sys.argv[1])
hosts = yaml.safe_load(open(yaml_path))['hosts']
for name, h in sorted(hosts.items()):
    result = subprocess.run(['ssh', '-o', 'ConnectTimeout=5', h['ssh'], 'hostname; uptime'],
                          capture_output=True, text=True, timeout=10)
    status = "OK" if result.returncode == 0 else "FAIL"
    print(f"{name}: {status}")
PY
```

## Related Skills

- **multi-agent-dispatch**: Full dx-dispatch capabilities for async/parallel dispatch
- **canonical-targets**: Shell exports for CANONICAL_VMS array (no PyYAML dependency)
- **vm-bootstrap**: Setting up new VMs with required tooling

## Resources

- `~/agent-skills/configs/fleet_hosts.yaml` - Authoritative fleet registry
- `~/agent-skills/scripts/canonical-targets.sh` - Shell exports (no PyYAML needed)
- `~/agent-skills/docs/CANONICAL_TARGETS.md` - Human-readable docs

---

**Last Updated:** 2026-02-14
**Skill Type:** Workflow / Infrastructure
**Average Duration:** 2-5 minutes
