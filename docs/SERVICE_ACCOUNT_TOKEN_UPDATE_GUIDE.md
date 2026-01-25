# Service Account Token Update Guide

**When:** After 1Password daily rate limit resets (~18 hours from rate limit)
**Or:** After upgrading to Business tier / deploying Connect Server

## Step 1: Create 3 Service Accounts (1Password.com)

1. Go to https://my.1password.com
2. Navigate to **Developer > Directory > Other > Service Accounts**
3. Click **Create a Connect server** (or "Create Service Account")

Create these 3 service accounts:

| Service Account | Purpose | VM | Vault |
|-----------------|---------|-----|-------|
| `opencode-cleanup` | Delete stale OpenCode sessions | homedesktop-wsl | Dev |
| `auto-checkpoint-epyc6` | GLM commit messages for auto-checkpoint | epyc6 | Dev |
| `auto-checkpoint-macmini` | GLM commit messages for auto-checkpoint | macmini | Dev |

**For each service account:**
1. Give it a descriptive name (e.g., "opencode-cleanup - homedesktop-wsl")
2. Select the "Dev" vault
3. Choose appropriate access level (read-only is fine for Tier 2 secrets)
4. **IMPORTANT:** Download the token immediately (only shown once!)

## Step 2: Distribute Tokens to VMs

### homedesktop-wsl (opencode-cleanup token)

```bash
# SSH into homedesktop-wsl
ssh fengning@homedesktop-wsl

# Create token file
cat > ~/.config/systemd/user/opencode-cleanup-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF

# Set permissions
chmod 600 ~/.config/systemd/user/opencode-cleanup-token

# Verify
cat ~/.config/systemd/user/opencode-cleanup-token
```

### epyc6 (auto-checkpoint token)

```bash
# SSH into epyc6 (or run locally if you're on epyc6)
ssh fengning@epyc6

# Create token file
cat > ~/.config/systemd/user/auto-checkpoint-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF

# Set permissions
chmod 600 ~/.config/systemd/user/auto-checkpoint-token

# Verify
cat ~/.config/systemd/user/auto-checkpoint-token
```

### macmini (auto-checkpoint token)

```bash
# SSH into macmini
ssh fengning@macmini

# Create token file
cat > ~/.config/systemd/user/auto-checkpoint-token << 'EOF'
PASTE_YOUR_TOKEN_HERE
EOF

# Set permissions
chmod 600 ~/.config/systemd/user/auto-checkpoint-token

# Verify
cat ~/.config/systemd/user/auto-checkpoint-token
```

## Step 3: Update Systemd Services to Use New Tokens

### homedesktop-wsl (opencode-cleanup)

```bash
ssh fengning@homedesktop-wsl

# Check if opencode-cleanup service exists
systemctl --user list-units | grep opencode

# If it exists, update it to use the new token:
cat > ~/.config/systemd/user/opencode-cleanup.service << 'EOF'
[Unit]
Description=OpenCode Session Cleanup
After=network.target

[Service]
Type=oneshot
ExecStart=/home/feng/agent-skills/slack-coordination/opencode-cleanup.sh
Environment=OP_SERVICE_ACCOUNT_TOKEN_FILE=%h/.config/systemd/user/opencode-cleanup-token

# Rate limiting
RestartSec=30
Restart=on-failure

[Install]
WantedBy=default.target
EOF

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart opencode-cleanup.service
systemctl --user status opencode-cleanup.service
```

### epyc6 (auto-checkpoint)

```bash
# On epyc6
# Update the opencode service to use the dedicated token
# (Currently using generic op_token, should switch to auto-checkpoint-token)

cat > ~/.config/systemd/user/opencode.service << 'EOF'
[Unit]
Description=OpenCode AI Server
After=network.target

[Service]
LoadCredential=auto-checkpoint-token:%h/.config/systemd/user/auto-checkpoint-token
EnvironmentFile=%h/.agent-env
ExecStart=/bin/bash -c 'export OP_SERVICE_ACCOUNT_TOKEN="$(cat $CREDENTIALS_DIRECTORY/auto-checkpoint-token)"; exec /home/linuxbrew/.linuxbrew/bin/op run -- /home/linuxbrew/.linuxbrew/bin/opencode serve --port 4105'

# Rate limiting
RestartSec=30
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user restart opencode.service
systemctl --user status opencode.service
```

### macmini (auto-checkpoint)

```bash
ssh fengning@macmini

# Update any services using op run to use the new token
# Check what services exist:
systemctl --user list-units | grep -i "op\|slack"

# For each service, update the LoadCredential line:
# LoadCredential=auto-checkpoint-token:%h/.config/systemd/user/auto-checkpoint-token

# Then reload and restart
systemctl --user daemon-reload
```

## Step 4: Update Secret Cache with New Token

After updating the service tokens, update the secret cache to use the new token for ZAI_API_KEY:

```bash
# On epyc6
# The secret cache already has ZAI_API_KEY from .zshrc
# Verify it still works:
source ~/.config/secret-cache/secrets.env
echo "Key present: ${ZAI_API_KEY:0:10}..."

# On macmini
ssh fengning@macmini
source ~/.config/secret-cache/secrets.env
echo "Key present: ${ZAI_API_KEY:0:10}..."

# On homedesktop-wsl
# Needs ZAI_API_KEY added to .zshrc first, then:
ssh fengning@homedesktop-wsl
# Add to ~/.zshrc: export ZAI_API_KEY="..."
source ~/.zshrc
echo "export ZAI_API_KEY=$ZAI_API_KEY" > ~/.config/secret-cache/secrets.env
```

## Step 5: Verify All Services

```bash
# Check each VM
for vm in homedesktop-wsl macmini epyc6; do
  echo "=== $vm ==="
  ssh fengning@$vm "systemctl --user list-units | grep -E 'opencode|slack|auto' | grep '\.service' | grep 'active\|failed'"
done

# Verify token authentication
ssh fengning@homedesktop-wsl "export OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/systemd/user/opencode-cleanup-token) && op whoami"
ssh fengning@macmini "export OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/systemd/user/auto-checkpoint-token) && op whoami"
ssh feng@epyc6 "export OP_SERVICE_ACCOUNT_TOKEN=\$(cat ~/.config/systemd/user/auto-checkpoint-token) && op whoami"
```

## Step 6: Clean Up Old Token

After verifying new tokens work:

```bash
# On each VM, backup then remove old op_token
mv ~/.config/systemd/user/op_token ~/.config/systemd/user/op_token.old.$(date +%Y%m%d)
```

## Step 7: Update Beads

```bash
# Mark 5f2.1 as completed
bd update agent-skills-5f2.1 --status="closed"
bd close agent-skills-5f2
```

---

## Summary of Token Distribution

| VM | Service Account | Token File | Used By |
|----|-----------------|------------|---------|
| homedesktop-wsl | opencode-cleanup | `~/.config/systemd/user/opencode-cleanup-token` | opencode-cleanup.service |
| epyc6 | auto-checkpoint-epyc6 | `~/.config/systemd/user/auto-checkpoint-token` | opencode.service, slack-coordinator.service |
| macmini | auto-checkpoint-macmini | `~/.config/systemd/user/auto-checkpoint-token` | (future services) |

**Security Notes:**
- All token files must be `chmod 600`
- All service accounts are Tier 2 (read-only, low-risk)
- Tokens should be rotated every 30 days
- Never commit tokens to git

---

**Document:** `docs/SERVICE_ACCOUNT_TOKEN_UPDATE_GUIDE.md`
**For:** Tech-Lead / Founder
**When:** After 1Password rate limit resets OR after Business tier upgrade
