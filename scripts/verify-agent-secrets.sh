#!/usr/bin/env bash
#
# verify-agent-secrets.sh
#
# Validates that the current environment (or Service Account) has access to
# required secrets in 1Password. Use this to verify setup after running
# create-op-credential.sh.
#
set -euo pipefail

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check for op CLI
if ! command -v op &> /dev/null; then
    echo -e "${RED}❌ 'op' CLI not found.${NC} Please install 1Password CLI."
    exit 1
fi

# Ensure OP_SERVICE_ACCOUNT_TOKEN is set
if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    HOSTNAME=$(hostname)
    TOKEN_FILE="$HOME/.config/systemd/user/op-${HOSTNAME}-token"
    
    if [[ -f "$TOKEN_FILE" ]]; then
        echo -e "${CYAN}ℹ️  Sourcing token from $TOKEN_FILE${NC}"
        export OP_SERVICE_ACCOUNT_TOKEN=$(cat "$TOKEN_FILE")
    else
        echo -e "${RED}❌ OP_SERVICE_ACCOUNT_TOKEN not set and not found at $TOKEN_FILE${NC}"
        echo "   Run ~/agent-skills/scripts/create-op-credential.sh first."
        exit 1
    fi
fi

echo -e "🔒 Verifying access to 'Agent-Secrets-Production'..."

# Fetch item details
ITEM_NAME="Agent-Secrets-Production"
VAULT="dev"
ITEM_JSON=$(op item get "$ITEM_NAME" --vault "$VAULT" --format json 2>/dev/null || echo "")

if [[ -z "$ITEM_JSON" ]]; then
    echo -e "${RED}❌ Could not access item '$ITEM_NAME' in vault '$VAULT'.${NC}"
    echo "   Possible causes:"
    echo "   1. Service Account does not have access to '$VAULT' vault."
    echo "   2. Item '$ITEM_NAME' does not exist."
    exit 1
else
    echo -e "${GREEN}✅ Access validated for '$ITEM_NAME'${NC}"
fi

# Check critical fields
REQUIRED_FIELDS=(
    "GITHUB_TOKEN"
    "RAILWAY_TOKEN"
    "ZAI_API_KEY"
    "SLACK_BOT_TOKEN"
    "SLACK_APP_TOKEN"
)

MISSING=0
for FIELD in "${REQUIRED_FIELDS[@]}"; do
    VALUE=$(echo "$ITEM_JSON" | jq -r ".fields[] | select(.label==\"$FIELD\") | .value // empty")
    
    if [[ -z "$VALUE" || "$VALUE" == "placeholder_replace_me" ]]; then
        echo -e "${RED}❌ Missing/Placeholder: $FIELD${NC}"
        MISSING=1
    else
        echo -e "${GREEN}✅ Found: $FIELD${NC}"
    fi
done

if [[ "$MISSING" -eq 1 ]]; then
    echo -e "\n${YELLOW}⚠️  Some secrets are missing or placeholders.${NC}"
    echo "   Please update them using 'op item edit \"$ITEM_NAME\" --vault \"$VAULT\" $FIELD=value'"
    exit 1
fi

echo -e "\n${GREEN}✨ All critical secrets validated!${NC}"
exit 0
