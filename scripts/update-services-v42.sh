#!/bin/bash
# ============================================================
# UPDATE SYSTEMD SERVICES FOR V4.2 (ENCRYPTED CREDENTIALS)
# ============================================================
#
# Updates opencode.service and slack-coordinator.service
# to use LoadCredentialEncrypted for secure token injection
#
# Usage: ./update-services-v42.sh [vm]
#   vm: optional, "all" to update all VMs (default: local only)
#
# ============================================================

set -euo pipefail

VM="${1:-local}"

# Function to update services on a VM
update_services() {
  local vm_name="$1"
  local is_local="$2"

  echo "=== Checking services on $vm_name ==="

  if [[ "$is_local" == "true" ]]; then
    # Local updates
    update_services_local
  else
    # Remote updates via SSH
    ssh "$vm_name" bash <<'ENDSSH'
      # Function to update services locally
      update_services_local() {
        # Check if already V4.2
        if systemctl --user show opencode.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
          echo "✅ opencode.service already configured for V4.2 (LoadCredentialEncrypted)"
        else
          # Backup V4.1 services
          if [[ -f ~/.config/systemd/user/opencode.service ]]; then
            BACKUP_FILE="${HOME}/.config/systemd/user/opencode.service.v41.backup.$(date +%Y%m%d_%H%M%S)"
            cp ~/.config/systemd/user/opencode.service "$BACKUP_FILE"
            echo "✅ Backed up opencode.service to: $BACKUP_FILE"
          fi
        fi

        if systemctl --user show slack-coordinator.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
          echo "✅ slack-coordinator.service already configured for V4.2 (LoadCredentialEncrypted)"
        else
          # Backup V4.1 services
          if [[ -f ~/.config/systemd/user/slack-coordinator.service ]]; then
            BACKUP_FILE="${HOME}/.config/systemd/user/slack-coordinator.service.v41.backup.$(date +%Y%m%d_%H%M%S)"
            cp ~/.config/systemd/user/slack-coordinator.service "$BACKUP_FILE"
            echo "✅ Backed up slack-coordinator.service to: $BACKUP_FILE"
          fi
        fi

        # Check if already V4.2
        NEEDS_UPDATE=false
        if ! systemctl --user show opencode.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
          NEEDS_UPDATE=true
        fi
        if ! systemctl --user show slack-coordinator.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
          NEEDS_UPDATE=true
        fi

        if [[ "$NEEDS_UPDATE" == "false" ]]; then
          echo "✅ All services already configured for V4.2"
          echo ""
          return 0
        fi

        # Create V4.2 opencode.service
        cat > ~/.config/systemd/user/opencode.service.v42.new <<'SERVICEEOF'
[Unit]
Description=OpenCode AI Server (V4.2.1 - Scoped Env + .cred)
After=network.target

[Service]
Type=simple
Environment="PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin"

# V4.2.1 Security: Load Encrypted Credential with fallback
# Tries LoadCredentialEncrypted first (TPM-protected), falls back to LoadCredential (file-permission-only)
LoadCredentialEncrypted=op_token:%h/.config/systemd/user/op_token.cred
LoadCredential=op_token:%h/.config/systemd/user/op_token

# Use SCOPED env file (not shared ~/.agent-env)
# op run resolves op:// references at runtime
ExecStart=/bin/bash -c 'export OP_SERVICE_ACCOUNT_TOKEN="$(cat $CREDENTIALS_DIRECTORY/op_token)"; exec /home/linuxbrew/.linuxbrew/bin/op run --env-file=%h/.config/opencode/.env -- /home/linuxbrew/.linuxbrew/bin/opencode serve --port 4105 --hostname 0.0.0.0'

Restart=on-failure
RestartSec=5
WorkingDirectory=%h/agent-skills
MemoryMax=4G

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/op %h/.config/opencode %h/.local/state/opencode

[Install]
WantedBy=default.target
SERVICEEOF

        # Create V4.2 slack-coordinator.service
        cat > ~/.config/systemd/user/slack-coordinator.service.v42.new <<'SERVICEEOF'
[Unit]
Description=Slack Coordination Service (V4.2.1 - Scoped Env + .cred)
After=network.target

[Service]
Type=simple
Environment="PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin"

# V4.2.1 Security: Load Encrypted Credential with fallback
LoadCredentialEncrypted=op_token:%h/.config/systemd/user/op_token.cred
LoadCredential=op_token:%h/.config/systemd/user/op_token

# Use SCOPED env file (not shared ~/.agent-env)
# op run resolves op:// references at runtime
WorkingDirectory=%h/agent-skills/slack-coordination
ExecStart=/bin/bash -c 'export OP_SERVICE_ACCOUNT_TOKEN="$(cat $CREDENTIALS_DIRECTORY/op_token)"; exec /home/linuxbrew/.linuxbrew/bin/op run --env-file=%h/.config/slack-coordinator/.env -- %h/agent-skills/slack-coordination/.venv/bin/python slack-coordinator.py'

Restart=on-failure
RestartSec=5
MemoryMax=2G

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/op %h/.config/slack-coordinator %h/.local/state/slack-coordinator

[Install]
WantedBy=default.target
SERVICEEOF

        # Install V4.2 services
        mv ~/.config/systemd/user/opencode.service.v42.new ~/.config/systemd/user/opencode.service
        mv ~/.config/systemd/user/slack-coordinator.service.v42.new ~/.config/systemd/user/slack-coordinator.service

        # Reload systemd
        systemctl --user daemon-reload

        # Restart services
        systemctl --user restart opencode.service
        systemctl --user restart slack-coordinator.service

        # Verify
        echo "Verifying services..."
        if systemctl --user is-active opencode.service > /dev/null 2>&1; then
          echo "✅ opencode.service running"
        else
          echo "❌ opencode.service failed to start"
          journalctl --user -u opencode.service -n 20 --no-pager
          exit 1
        fi

        if systemctl --user is-active slack-coordinator.service > /dev/null 2>&1; then
          echo "✅ slack-coordinator.service running"
        else
          echo "❌ slack-coordinator.service failed to start"
          journalctl --user -u slack-coordinator.service -n 20 --no-pager
          exit 1
        fi
      }

      update_services_local
ENDSSH
  fi
}

# Local update function
update_services_local() {
  # Check if already V4.2
  if systemctl --user show opencode.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
    echo "✅ opencode.service already configured for V4.2 (LoadCredentialEncrypted)"
  else
    # Backup V4.1 services with timestamp
    if [[ -f ~/.config/systemd/user/opencode.service ]]; then
      BACKUP_FILE="${HOME}/.config/systemd/user/opencode.service.v41.backup.$(date +%Y%m%d_%H%M%S)"
      cp ~/.config/systemd/user/opencode.service "$BACKUP_FILE"
      echo "✅ Backed up opencode.service to: $BACKUP_FILE"
    fi
  fi

  if systemctl --user show slack-coordinator.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
    echo "✅ slack-coordinator.service already configured for V4.2 (LoadCredentialEncrypted)"
  else
    # Backup V4.1 services with timestamp
    if [[ -f ~/.config/systemd/user/slack-coordinator.service ]]; then
      BACKUP_FILE="${HOME}/.config/systemd/user/slack-coordinator.service.v41.backup.$(date +%Y%m%d_%H%M%S)"
      cp ~/.config/systemd/user/slack-coordinator.service "$BACKUP_FILE"
      echo "✅ Backed up slack-coordinator.service to: $BACKUP_FILE"
    fi
  fi

  # Check if already V4.2
  NEEDS_UPDATE=false
  if ! systemctl --user show opencode.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
    NEEDS_UPDATE=true
  fi
  if ! systemctl --user show slack-coordinator.service 2>/dev/null | grep -q "LoadCredentialEncrypted"; then
    NEEDS_UPDATE=true
  fi

  if [[ "$NEEDS_UPDATE" == "false" ]]; then
    echo "✅ All services already configured for V4.2"
    echo ""
    return 0
  fi

  # Create V4.2 opencode.service
  cat > ~/.config/systemd/user/opencode.service.v42.new <<'EOF'
[Unit]
Description=OpenCode AI Server (V4.2.1 - Scoped Env + .cred)
After=network.target

[Service]
Type=simple
Environment="PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin"

# V4.2.1 Security: Load Encrypted Credential with fallback
LoadCredentialEncrypted=op_token:%h/.config/systemd/user/op_token.cred
LoadCredential=op_token:%h/.config/systemd/user/op_token

# Use SCOPED env file (per-service, NOT shared ~/.agent-env)
ExecStart=/bin/bash -c 'export OP_SERVICE_ACCOUNT_TOKEN="$(cat $CREDENTIALS_DIRECTORY/op_token)"; exec /home/linuxbrew/.linuxbrew/bin/op run --env-file=%h/.config/opencode/.env -- /home/linuxbrew/.linuxbrew/bin/opencode serve --port 4105 --hostname 0.0.0.0'

Restart=on-failure
RestartSec=5
WorkingDirectory=%h/agent-skills
MemoryMax=4G

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/op %h/.config/opencode %h/.local/state/opencode

[Install]
WantedBy=default.target
EOF

  # Create V4.2 slack-coordinator.service
  cat > ~/.config/systemd/user/slack-coordinator.service.v42.new <<'EOF'
[Unit]
Description=Slack Coordination Service (V4.2.1 - Scoped Env + .cred)
After=network.target

[Service]
Type=simple
Environment="PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin"

# V4.2.1 Security: Load Encrypted Credential with fallback
LoadCredentialEncrypted=op_token:%h/.config/systemd/user/op_token.cred
LoadCredential=op_token:%h/.config/systemd/user/op_token

# Use SCOPED env file (not shared ~/.agent-env)
# op run resolves op:// references at runtime
WorkingDirectory=%h/agent-skills/slack-coordination
ExecStart=/bin/bash -c 'export OP_SERVICE_ACCOUNT_TOKEN="$(cat $CREDENTIALS_DIRECTORY/op_token)"; exec /home/linuxbrew/.linuxbrew/bin/op run --env-file=%h/.config/slack-coordinator/.env -- %h/agent-skills/slack-coordination/.venv/bin/python slack-coordinator.py'

Restart=on-failure
RestartSec=5
MemoryMax=2G

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/op %h/.config/slack-coordinator %h/.local/state/slack-coordinator

[Install]
WantedBy=default.target
EOF

  # Install V4.2 services
  mv ~/.config/systemd/user/opencode.service.v42.new ~/.config/systemd/user/opencode.service
  mv ~/.config/systemd/user/slack-coordinator.service.v42.new ~/.config/systemd/user/slack-coordinator.service

  # Reload systemd
  systemctl --user daemon-reload

  # Restart services
  systemctl --user restart opencode.service
  systemctl --user restart slack-coordinator.service

  # Verify
  echo ""
  echo "Verifying services..."
  if systemctl --user is-active opencode.service > /dev/null 2>&1; then
    echo "✅ opencode.service running"
  else
    echo "❌ opencode.service failed to start"
    journalctl --user -u opencode.service -n 20 --no-pager
    exit 1
  fi

  if systemctl --user is-active slack-coordinator.service > /dev/null 2>&1; then
    echo "✅ slack-coordinator.service running"
  else
    echo "❌ slack-coordinator.service failed to start"
    journalctl --user -u slack-coordinator.service -n 20 --no-pager
    exit 1
  fi
}

# Main execution
if [[ "$VM" == "all" ]]; then
  # Update all Linux VMs (macmini uses native 1Password app)
  echo "=== Updating Linux VMs ==="
  echo ""

  update_services "epyc6" true
  echo ""

  update_services "fengning@homedesktop-wsl" false
  echo ""

  echo "=== All Linux VMs updated ==="
  echo "⏭️  macmini skipped (uses native 1Password app)"
else
  # Update local only
  update_services "epyc6" true
fi