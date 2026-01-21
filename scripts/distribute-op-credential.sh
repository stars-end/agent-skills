#!/bin/bash
# ============================================================
# DISTRIBUTE 1PASSWORD CREDENTIAL
# ============================================================
#
# Copies the local ~/.config/systemd/user/op_token to all
# configured remote VMs (macmini, homedesktop-wsl).
#
# Usage: ./distribute-op-credential.sh
# ============================================================

set -euo pipefail

CRED_FILE="${HOME}/.config/systemd/user/op_token"

if [[ ! -f "$CRED_FILE" ]]; then
  echo "❌ Credential file not found: $CRED_FILE"
  echo "Run create-op-credential.sh first"
  exit 1
fi

# Target VMs from vm-endpoints.json or hardcoded list
TARGETS=(
  "fengning@macmini"
  "fengning@homedesktop-wsl"
)

echo "=== Distributing Credential to Remote VMs ==="

# 1. Get the Plaintext Token (from local source)
# We need the plaintext to re-encrypt for the target host
if [ -f "${CRED_FILE}.cred" ] && command -v systemd-creds >/dev/null 2>&1; then
    echo "🔓 Decrypting local credential for distribution..."
    TOKEN=$(systemd-creds decrypt "${CRED_FILE}.cred")
elif [ -f "$CRED_FILE" ]; then
    echo "📖 Reading local plaintext credential..."
    TOKEN=$(cat "$CRED_FILE")
else
    echo "❌ No valid credential file found to distribute."
    exit 1
fi

for target in "${TARGETS[@]}"; do
  echo "📤 Distributing to $target..."

  # Create remote directory
  ssh -o ConnectTimeout=5 "$target" "mkdir -p ~/.config/systemd/user/" || {
      echo "❌ Failed to connect to $target"
      continue
  }

  # 2. Distribute & Encrypt (Host-Bound)
  # We pipe the token to the remote host and encrypt it THERE.
  # This solves the "Host Key" issue.
  
  if ssh -o ConnectTimeout=5 "$target" "command -v systemd-creds >/dev/null"; then
      echo "   🔒 Encrypting with remote systemd-creds..."
      echo -n "$TOKEN" | ssh -o ConnectTimeout=5 "$target" "systemd-creds encrypt --name=op_token - ~/.config/systemd/user/op_token.cred"
      # Remove plaintext if it exists (cleanup)
      ssh -o ConnectTimeout=5 "$target" "rm -f ~/.config/systemd/user/op_token"
      echo "   ✅ Remote encryption successful (plaintext removed)."
  else
      echo "   ⚠️  Remote systemd-creds not found. Using protected plaintext."
      echo -n "$TOKEN" | ssh -o ConnectTimeout=5 "$target" "cat > ~/.config/systemd/user/op_token && chmod 600 ~/.config/systemd/user/op_token"
      echo "   ✅ Remote install successful (mode 600)."
  fi

done

# Clear token from memory
unset TOKEN

echo ""
echo "=== Distribution Complete ==="
