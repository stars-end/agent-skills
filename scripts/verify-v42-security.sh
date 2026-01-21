#!/bin/bash
# ============================================================
# V4.2.1 SECURITY AUDIT
# ============================================================
#
# Verifies the security posture of the 1Password Service Account
# integration with ENCRYPTED CREDENTIALS and SCOPED ENV FILES.
#
# Checks:
# 1. Encrypted credential file (.cred) preferred
# 2. Plaintext token file (fallback) - warn if both exist
# 3. Credential file permissions (must be 0600)
# 4. No secrets in scoped env files (only op:// references)
# 5. Services use LoadCredentialEncrypted (not just LoadCredential)
# 6. Services are running
#
# ============================================================

set -u

CRED_ENCRYPTED="${HOME}/.config/systemd/user/op_token.cred"
CRED_PLAINTEXT="${HOME}/.config/systemd/user/op_token"
ENV_DIR="${HOME}/.config"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "=== V4.2.1 Security Audit ==="
echo "Host: $(hostname)"
echo "Date: $(date)"
echo ""

# 1. Check Encrypted Credential (Preferred)
echo "--- Credential Files ---"
if [ -f "$CRED_ENCRYPTED" ]; then
    # Check permissions
    PERMS=$(stat -c "%a" "$CRED_ENCRYPTED" 2>/dev/null || stat -f "%A" "$CRED_ENCRYPTED")
    if [ "$PERMS" == "600" ] || [ "$PERMS" == "600" ]; then
        echo -e "${GREEN}✅ Encrypted credential exists: $CRED_ENCRYPTED (perms: $PERMS)${NC}"
    else
        echo -e "${YELLOW}⚠️  Encrypted credential has insecure permissions ($PERMS): $CRED_ENCRYPTED${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠️  Encrypted credential not found: $CRED_ENCRYPTED${NC}"
    echo "   (Run: ./scripts/create-op-credential.sh)"
    WARNINGS=$((WARNINGS+1))
fi

# 2. Check Plaintext Credential (Fallback, warn if both exist)
if [ -f "$CRED_PLAINTEXT" ]; then
    if [ -f "$CRED_ENCRYPTED" ]; then
        echo -e "${RED}❌ Both .cred and plaintext token exist! Remove plaintext: $CRED_PLAINTEXT${NC}"
        echo "   Run: rm $CRED_PLAINTEXT"
        ERRORS=$((ERRORS+1))
    else
        PERMS=$(stat -c "%a" "$CRED_PLAINTEXT" 2>/dev/null || stat -f "%A" "$CRED_PLAINTEXT")
        if [ "$PERMS" == "600" ]; then
            echo -e "${YELLOW}⚠️  Plaintext fallback (OK if no TPM): $CRED_PLAINTEXT (perms: $PERMS)${NC}"
            echo "   Recommendation: Use encrypted credential when possible"
            WARNINGS=$((WARNINGS+1))
        else
            echo -e "${RED}❌ Insecure plaintext token permissions ($PERMS): $CRED_PLAINTEXT${NC}"
            ERRORS=$((ERRORS+1))
        fi
    fi
fi

if [ ! -f "$CRED_ENCRYPTED" ] && [ ! -f "$CRED_PLAINTEXT" ]; then
    echo -e "${RED}❌ No credential file found!${NC}"
    echo "   Run: ./scripts/create-op-credential.sh"
    ERRORS=$((ERRORS+1))
fi

# 3. Check for Backups (Security Risk)
echo ""
echo "--- Backup Files ---"
BACKUPS=$(find "${HOME}/.config/systemd/user/" -name "op_token*.backup*" -o -name "op_token*.bak" 2>/dev/null)
if [ -z "$BACKUPS" ]; then
    echo -e "${GREEN}✅ No backup files found${NC}"
else
    echo -e "${RED}❌ Backup files found (Potential Leak):${NC}"
    echo "$BACKUPS"
    echo "   Run: rm -f $BACKUPS"
    ERRORS=$((ERRORS+1))
fi

# 4. Check Scoped Env Files for Secrets (should only have op:// references)
echo ""
echo "--- Scoped Env Files ---"
PLAINTEXT_SECRETS=0

# Check opencode env
if [ -f "$ENV_DIR/opencode/.env" ]; then
    # Find lines with secret patterns that are NOT op:// references
    if grep -E "(ANTHROPIC_AUTH_TOKEN|SLACK.*TOKEN|SECRET|PASSWORD|OPENAI_API_KEY)" "$ENV_DIR/opencode/.env" 2>/dev/null | grep -v "op://" >/dev/null; then
        echo -e "${RED}❌ Plaintext secrets found in: $ENV_DIR/opencode/.env${NC}"
        echo "   (Should only contain op:// references)"
        PLAINTEXT_SECRETS=$((PLAINTEXT_SECRETS+1))
    else
        echo -e "${GREEN}✅ No plaintext secrets in: $ENV_DIR/opencode/.env${NC}"
    fi
fi

# Check slack-coordinator env
if [ -f "$ENV_DIR/slack-coordinator/.env" ]; then
    if grep -E "(ANTHROPIC_AUTH_TOKEN|SLACK.*TOKEN|SECRET|PASSWORD|OPENAI_API_KEY)" "$ENV_DIR/slack-coordinator/.env" 2>/dev/null | grep -v "op://" >/dev/null; then
        echo -e "${RED}❌ Plaintext secrets found in: $ENV_DIR/slack-coordinator/.env${NC}"
        echo "   (Should only contain op:// references)"
        PLAINTEXT_SECRETS=$((PLAINTEXT_SECRETS+1))
    else
        echo -e "${GREEN}✅ No plaintext secrets in: $ENV_DIR/slack-coordinator/.env${NC}"
    fi
fi

# Check for global .agent-env (DEPRECATED in V4.2.1)
if [ -f "$HOME/.agent-env" ]; then
    echo -e "${YELLOW}⚠️  Global .agent-env found (DEPRECATED in V4.2.1)${NC}"
    echo "   Should use scoped env files: ~/.config/<service>/.env"
    WARNINGS=$((WARNINGS+1))

    if grep -E "(ANTHROPIC_AUTH_TOKEN|SLACK.*TOKEN|SECRET|PASSWORD|OPENAI_API_KEY)" "$HOME/.agent-env" 2>/dev/null | grep -v "op://" >/dev/null; then
        echo -e "${RED}❌ Plaintext secrets in global .agent-env${NC}"
        PLAINTEXT_SECRETS=$((PLAINTEXT_SECRETS+1))
    fi
fi

if [ $PLAINTEXT_SECRETS -eq 0 ]; then
    echo -e "${GREEN}✅ No plaintext secrets in env files${NC}"
fi

# 5. Service Status & LoadCredential Check
echo ""
echo "--- Service Status ---"

# Check if services use LoadCredentialEncrypted
for service in opencode slack-coordinator; do
    SERVICE_FILE="${HOME}/.config/systemd/user/${service}.service"
    if systemctl --user is-active "$service" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $service: Active${NC}"

        # Check for LoadCredentialEncrypted
        if [ -f "$SERVICE_FILE" ]; then
            if grep -q "LoadCredentialEncrypted" "$SERVICE_FILE"; then
                echo -e "${GREEN}   └─ Uses LoadCredentialEncrypted ✅${NC}"
            elif grep -q "LoadCredential=op_token" "$SERVICE_FILE"; then
                echo -e "${YELLOW}   └─ Uses LoadCredential (fallback, not encrypted)${NC}"
                WARNINGS=$((WARNINGS+1))
            else
                echo -e "${YELLOW}   └─ No LoadCredential directive found${NC}"
                WARNINGS=$((WARNINGS+1))
            fi
        fi
    else
        echo -e "${RED}❌ $service: Inactive${NC}"
        ERRORS=$((ERRORS+1))
    fi
done

# Summary
echo ""
echo "=== Audit Summary ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  $WARNINGS warning(s) found${NC}"
    echo "   Review and fix for optimal security posture."
    exit 0
else
    echo -e "${RED}❌ $ERRORS error(s) + $WARNINGS warning(s) found${NC}"
    echo "   Fix errors before using services in production."
    exit 1
fi
