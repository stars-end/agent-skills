# Self-Hosted GitHub Actions Runner Setup

**Status**: Canonical reference for Stars-End self-hosted runners
**Related**: bd-md4i (Infrastructure: Dedicated runner user + systemd isolation)

## Problem Statement

Running GitHub Actions self-hosted runners under your personal user account creates environment pollution:
- Workflows modify your development environment (e.g., `~/.agent/skills` symlinks)
- Your dev state affects CI reproducibility
- Security boundary is weak (runner has your permissions)
- No automatic restart on reboot

## Solution: Dedicated Runner User

Create a separate system user (`runner`) that owns all GitHub Actions runners, with systemd services for lifecycle management.

---

## Architecture

```
/home/runner/
├── .agent/
│   └── skills -> /home/runner/agent-skills
├── agent-skills/           # Cloned from stars-end/agent-skills
├── actions-runner-prime-radiant/
│   ├── config.sh
│   ├── run.sh
│   └── svc.sh
└── actions-runner-affordabot/
    ├── config.sh
    ├── run.sh
    └── svc.sh
```

**Key principles:**
1. **Isolation**: Runner user has its own home directory, separate from dev users
2. **Automation**: Systemd manages lifecycle (start, stop, restart on reboot)
3. **Permissions**: Runner user has minimal permissions (no sudo by default)
4. **Reproducibility**: Clean environment for each workflow run

---

## Setup Guide

### Phase 1: Create Runner User

```bash
# Create system user for running GitHub Actions
sudo useradd -m -s /bin/bash -c "GitHub Actions Runner" runner

# Optional: Add to docker group if workflows need Docker
# sudo usermod -aG docker runner

# Verify user created
id runner
# Output: uid=1001(runner) gid=1001(runner) groups=1001(runner)
```

### Phase 2: Setup Runner Environment

```bash
# Switch to runner user
sudo su - runner

# Clone agent-skills for DX tooling
git clone https://github.com/stars-end/agent-skills.git ~/agent-skills

# Setup skills mount
mkdir -p ~/.agent
ln -sfn ~/agent-skills ~/.agent/skills

# Verify mount
ls -la ~/.agent/skills
```

### Phase 3: Install GitHub Actions Runners

**For each repository (prime-radiant-ai, affordabot):**

```bash
# Still as runner user
cd ~

# Download runner (replace VERSION with latest from GitHub)
mkdir actions-runner-prime-radiant && cd actions-runner-prime-radiant
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-*.tar.gz

# Configure runner (you'll need a runner token from GitHub)
# Get token from: https://github.com/stars-end/prime-radiant-ai/settings/actions/runners/new
./config.sh \
  --url https://github.com/stars-end/prime-radiant-ai \
  --token YOUR_RUNNER_TOKEN \
  --name "$(hostname -s)-prime-radiant" \
  --labels "self-hosted,linux,x64" \
  --work _work

# Test runner manually first
./run.sh  # Press Ctrl+C to stop after verification
```

**Repeat for affordabot:**

```bash
cd ~
mkdir actions-runner-affordabot && cd actions-runner-affordabot
# ... same steps as above, but for affordabot repo
```

### Phase 4: Install as Systemd Services

```bash
# Still as runner user, in each runner directory

# For prime-radiant runner
cd ~/actions-runner-prime-radiant
sudo ./svc.sh install runner  # Install as systemd service for 'runner' user
sudo ./svc.sh start

# For affordabot runner
cd ~/actions-runner-affordabot
sudo ./svc.sh install runner
sudo ./svc.sh start

# Verify services are running
sudo systemctl status actions.runner.stars-end-prime-radiant-ai.*
sudo systemctl status actions.runner.stars-end-affordabot.*
```

### Phase 5: Verify Runner Registration

```bash
# Check runners are online
# Go to GitHub repo settings -> Actions -> Runners
# Should see runners with green "Idle" status

# Or check via systemctl
sudo systemctl list-units --type=service | grep actions.runner
```

---

## Migration from Personal User

If you already have runners running under your personal account:

### Step 1: Stop Old Runners

```bash
# As your personal user (feng)
cd ~/actions-runner-prime-radiant
./svc.sh stop   # If installed as service
# OR
# Just kill the nohup process if running in background

# Remove old runner registration
./config.sh remove --token YOUR_TOKEN

# Repeat for affordabot runner
```

### Step 2: Cleanup Old Files

```bash
# As your personal user
rm -rf ~/actions-runner-prime-radiant
rm -rf ~/actions-runner-affordabot

# Fix your personal ~/.agent/skills symlink
ln -sfn ~/agent-skills ~/.agent/skills
```

### Step 3: Install New Runners

Follow Phase 1-4 above to set up runners under `runner` user.

---

## Troubleshooting

### Runner Won't Start

```bash
# Check service status
sudo systemctl status actions.runner.stars-end-prime-radiant-ai.*

# Check logs
sudo journalctl -u actions.runner.stars-end-prime-radiant-ai.* -n 50

# Common issues:
# 1. Token expired -> Need to re-run config.sh with new token
# 2. Permissions -> Check runner user has access to required directories
# 3. Network -> Check firewall rules for GitHub API access
```

### Workflows Fail with "Permission Denied"

```bash
# Runner user may need additional permissions
# Add to specific groups:
sudo usermod -aG docker runner  # For Docker workflows
sudo usermod -aG sudo runner    # If workflows need sudo (NOT recommended)

# For specific file/directory access, use ACLs:
sudo setfacl -m u:runner:rwx /path/to/directory
```

### Runner Not Appearing in GitHub

```bash
# Verify runner is connected
cd ~/actions-runner-prime-radiant
sudo -u runner ./run.sh  # Run manually to see connection errors

# Re-register if needed
sudo -u runner ./config.sh remove
sudo -u runner ./config.sh --url ... --token ...
```

### ~/.agent/skills Still Getting Corrupted

```bash
# Verify runner user has its own skills mount
sudo -u runner ls -la ~/.agent/skills
# Should point to /home/runner/agent-skills

# If not, fix it:
sudo -u runner bash -c 'ln -sfn ~/agent-skills ~/.agent/skills'

# Also fix skills-validation.yml workflow (see bd-md4i.4)
```

---

## Maintenance

### Updating Runners

```bash
# Stop runner service
sudo systemctl stop actions.runner.stars-end-prime-radiant-ai.*

# As runner user
cd ~/actions-runner-prime-radiant
sudo -u runner ./config.sh remove

# Download new version
sudo -u runner curl -o actions-runner-linux-x64-NEW.tar.gz -L \
  https://github.com/actions/runner/releases/download/vNEW/actions-runner-linux-x64-NEW.tar.gz

# Extract (overwrites old files)
sudo -u runner tar xzf ./actions-runner-linux-x64-NEW.tar.gz

# Re-configure
sudo -u runner ./config.sh --url ... --token ...

# Restart service
sudo systemctl start actions.runner.stars-end-prime-radiant-ai.*
```

### Rotating Runner Tokens

Runner tokens expire after a few hours. For long-running installations:
1. Generate new runner token from GitHub
2. Stop service: `sudo systemctl stop actions.runner...`
3. Remove old config: `sudo -u runner ./config.sh remove`
4. Re-configure with new token
5. Start service: `sudo systemctl start actions.runner...`

### Monitoring Runner Health

```bash
# Check service status
sudo systemctl status actions.runner.stars-end-*

# Check recent logs
sudo journalctl -u actions.runner.stars-end-prime-radiant-ai.* --since "1 hour ago"

# Check GitHub UI
# Runners page shows last check-in time and status
```

---

## Security Considerations

### Minimal Permissions

Runner user should have:
- ✅ Read/write to its own home directory
- ✅ Execute permissions for required tools (git, docker, mise, etc.)
- ❌ NO sudo access (unless workflows explicitly require it)
- ❌ NO access to other users' home directories

### Secrets Handling

- Never log secrets in workflow output
- Use GitHub secrets for sensitive values
- Runner has access to repository secrets during workflow execution
- Secrets are masked in logs automatically

### Network Isolation

Consider:
- Firewall rules limiting runner's network access
- VPN/bastion for accessing internal resources
- Separate runner for public vs private repos

---

## References

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemctl.html)
- [Agent Skills Skills Plane](../SKILLS_PLANE.md)
- [DX Bootstrap Contract](../DX_BOOTSTRAP_CONTRACT.md)

---

## Quick Reference

**Check runner status:**
```bash
sudo systemctl status actions.runner.stars-end-*
```

**Restart runner:**
```bash
sudo systemctl restart actions.runner.stars-end-prime-radiant-ai.*
```

**View runner logs:**
```bash
sudo journalctl -u actions.runner.stars-end-prime-radiant-ai.* -f
```

**Switch to runner user:**
```bash
sudo su - runner
```

**Update agent-skills:**
```bash
sudo -u runner git -C ~runner/agent-skills pull origin main
```
