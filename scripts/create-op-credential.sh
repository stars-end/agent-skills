#!/bin/bash
# ============================================================
# CREATE PROTECTED 1PASSWORD CREDENTIAL (V4.3)
# ============================================================
#
# Creates a protected (chmod 600) credential file for 1Password
# service account. Uses hostname-based token naming convention.
#
# Usage: ./create-op-credential.sh [--force]
#   --force: Overwrite existing credential
#
# Naming: op-<hostname>-token (e.g., op-epyc6-token)
#
# ============================================================

set -euo pipefail

# Ensure we always prompt
unset OP_SERVICE_ACCOUNT_TOKEN

FORCE="${1:-}"
HOSTNAME=$(hostname)
TOKEN_NAME="op-${HOSTNAME}-token"
CRED_PLAINTEXT="${HOME}/.config/systemd/user/${TOKEN_NAME}"
CRED_ENCRYPTED="${HOME}/.config/systemd/user/${TOKEN_NAME}.cred"

echo "=== Creating Protected 1Password Credential (V4.3 - Hostname-Based) ==="
echo "Hostname: $HOSTNAME"
echo "Token file: $TOKEN_NAME"
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

# ENCRYPTION LOGIC (V4.5)
ENCRYPTED=false
if command -v systemd-creds >/dev/null 2>&1; then
    echo "🔒 Attempting systemd-creds encryption (TPM/Host Key protection)..."

    # Try encrypt to .cred file (may need sudo for credential.secret access)
    # Use sudo but write to user's home directory
    if echo -n "$OP_SERVICE_ACCOUNT_TOKEN" | sudo systemd-creds encrypt --name="${TOKEN_NAME}" - "${CRED_ENCRYPTED}" 2>/dev/null; then
        # Fix ownership to user
        sudo chown $USER:$USER "${CRED_ENCRYPTED}"
        sudo chmod 600 "${CRED_ENCRYPTED}"
        
        # Remove plaintext if it exists (cleanup)
        rm -f "$CRED_PLAINTEXT"

        echo "✅ Credential encrypted to ${CRED_ENCRYPTED}"
        echo "   (Only decryptable by systemd on this host)"
        ENCRYPTED=true
    else
        echo "⚠️  systemd-creds encryption failed (TPM unavailable or no sudo)"
        echo "   Falling back to filesystem permissions..."
    fi
fi

if [[ "$ENCRYPTED" != "true" ]]; then
    # Write token to file (plaintext with strict permissions)
    echo -n "$OP_SERVICE_ACCOUNT_TOKEN" > "$CRED_PLAINTEXT"

    # Set permissions
    chmod 600 "$CRED_PLAINTEXT"

    echo "✅ Credential installed to $CRED_PLAINTEXT (mode 600)"
    echo "   ⚠️  WARNING: Using plaintext fallback - consider using sudo for encryption"
fi

# Clear variable
unset OP_SERVICE_ACCOUNT_TOKEN