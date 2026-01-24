#!/bin/bash
# ============================================================
# DISTRIBUTE 1PASSWORD CREDENTIAL (V4.3)
# ============================================================
#
# Copies the local op-<hostname>-token to all configured
# remote VMs. Each VM gets its own hostname-based token.
#
# Usage: ./distribute-op-credential.sh
#
# Naming: op-<hostname>-token (e.g., op-macmini-token)
#
# ============================================================

set -euo pipefail

# Get local hostname and token name
LOCAL_HOSTNAME=$(hostname)
LOCAL_TOKEN_NAME="op-${LOCAL_HOSTNAME}-token"
LOCAL_CRED="${HOME}/.config/systemd/user/${LOCAL_TOKEN_NAME}"

if [[ ! -f "$LOCAL_CRED" ]]; then
  echo "❌ Credential file not found: $LOCAL_CRED"
  echo "Run create-op-credential.sh first on this host"
  exit 1
fi

# Target VMs with their expected token names
declare -A TARGETS
TARGETS["fengning@macmini"]="op-macmini-token"
TARGETS["fengning@homedesktop-wsl"]="op-homedesktop-wsl-token"

echo "=== Distributing Credential to Remote VMs ==="
echo "Local: $LOCAL_TOKEN_NAME"
echo ""

# 1. Get the Plaintext Token (from local source)
# We need the plaintext to re-encrypt for the target host
if [ -f "${LOCAL_CRED}.cred" ] && command -v systemd-creds >/dev/null 2>&1; then
    echo "🔓 Decrypting local credential for distribution..."
    TOKEN=$(systemd-creds decrypt "${LOCAL_CRED}.cred")
elif [ -f "$LOCAL_CRED" ]; then
    echo "📖 Reading local plaintext credential..."
    TOKEN=$(cat "$LOCAL_CRED")
else
    echo "❌ No valid credential file found to distribute."
    exit 1
fi

for target in "${!TARGETS[@]}"; do
  remote_token="${TARGETS[$target]}"
  echo "📤 Distributing to $target (as $remote_token)..."

  # Create remote directory
  ssh -o ConnectTimeout=5 "$target" "mkdir -p ~/.config/systemd/user/" || {
      echo "❌ Failed to connect to $target"
      continue
  }

  # 2. Distribute & Encrypt (Host-Bound)
  if ssh -o ConnectTimeout=5 "$target" "command -v systemd-creds >/dev/null"; then
      echo "   🔒 Encrypting with remote systemd-creds..."
      echo -n "$TOKEN" | ssh -o ConnectTimeout=5 "$target" "systemd-creds encrypt --name=${remote_token} - ~/.config/systemd/user/${remote_token}.cred"
      # Remove plaintext if it exists (cleanup)
      ssh -o ConnectTimeout=5 "$target" "rm -f ~/.config/systemd/user/${remote_token}"
      echo "   ✅ Remote encryption successful (plaintext removed)."
  else
      echo "   ⚠️  Remote systemd-creds not found. Using protected plaintext."
      echo -n "$TOKEN" | ssh -o ConnectTimeout=5 "$target" "cat > ~/.config/systemd/user/${remote_token} && chmod 600 ~/.config/systemd/user/${remote_token}"
      echo "   ✅ Remote install successful (mode 600)."
  fi

  # 3. Update service files to use new token name
  echo "   🔧 Checking service files for $remote_token references..."
  ssh -o ConnectTimeout=5 "$target" "grep -l 'op_token' ~/.config/systemd/user/*.service 2>/dev/null" && {
      echo "   ⚠️  Service files still use old 'op_token' - manual update required"
  } || echo "   ✅ Service files already updated"

done

# Clear token from memory
unset TOKEN

echo ""
echo "=== Distribution Complete ==="
