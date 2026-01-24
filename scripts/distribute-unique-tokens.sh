#!/bin/bash
# ============================================================
# DISTRIBUTE UNIQUE 1PASSWORD TOKENS TO ALL VMs
# ============================================================
#
# Prompts for 3 unique service account tokens (one per host)
# and securely distributes each to its respective VM.
#
# Usage: ./distribute-unique-tokens.sh
#
# Naming: op-<hostname>-token
#
# Security:
# - Tokens transferred over SSH (encrypted)
# - systemd-creds encrypts at rest (host-bound) if available
# - Falls back to chmod 600 plaintext if systemd-creds missing
#
# ============================================================

set -euo pipefail

# Ensure we always prompt for tokens
unset OP_SERVICE_ACCOUNT_TOKEN

# Target VMs with their token names
declare -A TARGETS
TARGETS["feng@epyc6"]="op-epyc6-token"
TARGETS["fengning@homedesktop-wsl"]="op-homedesktop-wsl-token"
TARGETS["fengning@macmini"]="op-macmini-token"

echo "=== Distributing Unique 1Password Tokens to All VMs ==="
echo ""
echo "This script will prompt for 3 UNIQUE service account tokens."
echo "Each VM gets its own token."
echo ""

# Collect tokens first (don't store in file, just memory)
declare -A TOKENS

for target in "${!TARGETS[@]}"; do
  token_name="${TARGETS[$target]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Target: $target"
  echo "Token name: $token_name"
  echo ""
  printf "Paste 1Password service account token for %s: " "$target"
  read -s TOKENS[$target]
  echo ""

  # Validate token format
  token_value="${TOKENS[$target]}"
  if [[ ! "$token_value" =~ ^ops_ ]] || [[ ${#token_value} -lt 20 ]]; then
    echo "❌ Invalid token format (should start with 'ops_' and be at least 20 characters)"
    echo "   Your token length: ${#token_value}"
    exit 1
  fi
  echo "✅ Token format validated"
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All tokens collected. Distributing to VMs..."
echo ""

# Distribute each token to its target
for target in "${!TOKENS[@]}"; do
  token_value="${TOKENS[$target]}"
  token_name="${TARGETS[$target]}"

  echo "📤 Distributing to $target (as $token_name)..."

  # Test connection first
  if ! ssh -o ConnectTimeout=5 "$target" "hostname" >/dev/null 2>&1; then
    echo "❌ Failed to connect to $target (skipping)"
    continue
  fi

  # Create remote directory
  ssh -o ConnectTimeout=5 "$target" "mkdir -p ~/.config/systemd/user/" || {
      echo "❌ Failed to create directory on $target"
      continue
  }

  # Check if remote has systemd-creds
  if ssh -o ConnectTimeout=5 "$target" "command -v systemd-creds >/dev/null"; then
      echo "   🔒 Encrypting with remote systemd-creds..."
      echo -n "$token_value" | ssh -o ConnectTimeout=5 "$target" "systemd-creds encrypt --name=${token_name} - ~/.config/systemd/user/${token_name}.cred"
      # Remove plaintext if it exists (cleanup)
      ssh -o ConnectTimeout=5 "$target" "rm -f ~/.config/systemd/user/${token_name}"
      echo "   ✅ Encrypted to ${token_name}.cred (host-bound)"
  else
      echo "   ⚠️  Remote systemd-creds not found. Using protected plaintext."
      echo -n "$token_value" | ssh -o ConnectTimeout=5 "$target" "cat > ~/.config/systemd/user/${token_name} && chmod 600 ~/.config/systemd/user/${token_name}"
      echo "   ✅ Installed to ${token_name} (mode 600)"
  fi

  echo ""
done

# Clear all tokens from memory
for target in "${!TOKENS[@]}"; do
  unset TOKENS[$target]
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "=== Distribution Complete ==="
echo ""
echo "Next steps:"
echo "1. On each VM, restart services:"
echo "   systemctl --user daemon-reload"
echo "   systemctl --user restart opencode.service slack-coordinator.service"
echo ""
echo "2. Verify services are active:"
echo "   systemctl --user is-active opencode.service"
echo "   systemctl --user is-active slack-coordinator.service"
echo ""
