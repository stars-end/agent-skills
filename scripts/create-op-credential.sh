#!/bin/bash
# ============================================================
# CREATE PROTECTED 1PASSWORD CREDENTIAL (V4.2)
# ============================================================
#
# Creates a protected (chmod 600) credential file for 1Password
# service account. Uses standard file permissions instead of
# systemd-creds encryption to ensure compatibility across all
# VMs (including WSL where systemd-creds can fail).
#
# Usage: ./create-op-credential.sh [--force]
#   --force: Overwrite existing credential
#
# ============================================================

set -euo pipefail

# Ensure we always prompt
unset OP_SERVICE_ACCOUNT_TOKEN

FORCE="${1:-}"
CRED_PLAINTEXT="${HOME}/.config/systemd/user/op_token"
CRED_ENCRYPTED="${HOME}/.config/systemd/user/op_token.cred"

echo "=== Creating Protected 1Password Credential (V4.2 - Portable) ==="
echo ""

# Check if credential already exists (BOTH .cred and plaintext count)
if [[ -f "$CRED_ENCRYPTED" || -f "$CRED_PLAINTEXT" ]] && [[ "$FORCE" != "--force" ]]; then
  EXISTING_TYPE=""
  if [[ -f "$CRED_ENCRYPTED" ]]; then
    EXISTING_TYPE="encrypted ($CRED_ENCRYPTED)"
  fi
  if [[ -f "$CRED_PLAINTEXT" ]]; then
    if [[ -n "$EXISTING_TYPE" ]]; then
      EXISTING_TYPE="$EXISTING_TYPE and plaintext ($CRED_PLAINTEXT)"
    else
      EXISTING_TYPE="plaintext ($CRED_PLAINTEXT)"
    fi
  fi
  echo "⚠️  Credential already exists: $EXISTING_TYPE"
  echo ""
  echo "Options:"
  echo "  - Keep existing: No action needed"
  echo "  - Replace: Run with --force flag"
  exit 0
fi

# Backup existing credential if force (backup whichever exists)
if [[ "$FORCE" == "--force" ]]; then
  if [[ -f "$CRED_ENCRYPTED" ]]; then
    BACKUP_FILE="${CRED_ENCRYPTED}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CRED_ENCRYPTED" "$BACKUP_FILE"
    echo "✅ Backed up existing encrypted credential to: $BACKUP_FILE"
  fi
  if [[ -f "$CRED_PLAINTEXT" ]]; then
    BACKUP_FILE="${CRED_PLAINTEXT}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CRED_PLAINTEXT" "$BACKUP_FILE"
    echo "✅ Backed up existing plaintext credential to: $BACKUP_FILE"
  fi
fi

# Read token
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "Paste your 1Password service account token below:"
  printf "OP_SERVICE_ACCOUNT_TOKEN: "
  read -s OP_SERVICE_ACCOUNT_TOKEN
  echo ""
else
  echo "✅ Using OP_SERVICE_ACCOUNT_TOKEN from environment"
fi

# Ensure token is not empty
if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    echo "❌ Error: Token is empty."
    exit 1
fi

# Validate token format (starts with ops_ and has reasonable length)
if [[ ! "$OP_SERVICE_ACCOUNT_TOKEN" =~ ^ops_ ]] || [[ ${#OP_SERVICE_ACCOUNT_TOKEN} -lt 20 ]]; then
  echo "❌ Invalid token format (should start with 'ops_' and be at least 20 characters)"
  echo "   Your token length: ${#OP_SERVICE_ACCOUNT_TOKEN}"
  unset OP_SERVICE_ACCOUNT_TOKEN
  exit 1
fi

echo "Creating protected credential..."

# Create directory
mkdir -p ~/.config/systemd/user/

# ENCRYPTION LOGIC (V4.2)
if command -v systemd-creds >/dev/null 2>&1; then
    echo "🔒 Encrypting with systemd-creds (TPM/Host Key protection)..."

    # Encrypt to .cred file
    echo -n "$OP_SERVICE_ACCOUNT_TOKEN" | systemd-creds encrypt --name=op_token - "${CRED_ENCRYPTED}"

    # Remove plaintext if it exists (cleanup)
    rm -f "$CRED_PLAINTEXT"

    echo "✅ Credential encrypted to ${CRED_ENCRYPTED}"
    echo "   (Only decryptable by systemd on this host)"

    # Fix ownership
    chown $USER:$USER "${CRED_ENCRYPTED}" 2>/dev/null || true
else
    echo "⚠️  systemd-creds not found. Falling back to filesystem permissions."

    # Write token to file
    echo -n "$OP_SERVICE_ACCOUNT_TOKEN" > "$CRED_PLAINTEXT"

    # Set permissions
    chmod 600 "$CRED_PLAINTEXT"

    echo "✅ Credential installed to $CRED_PLAINTEXT (mode 600)"

    # Fix ownership
    chown $USER:$USER "$CRED_PLAINTEXT" 2>/dev/null || true
fi

# Clear variable
unset OP_SERVICE_ACCOUNT_TOKEN