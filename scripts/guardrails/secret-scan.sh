#!/usr/bin/env bash
# Secret Scanning Guardrail for agent-skills and prime-radiant-ai
# Detects common secret patterns to prevent committed credentials
# Usage: scripts/guardrails/secret-scan.sh [--fail] [--verbose]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERBOSE="${VERBOSE:-false}"
FAIL_ON_FIND="${FAIL_ON_FIND:-false}"
ISSUES_FILE="/tmp/secret-scan-issues.$$"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fail) FAIL_ON_FIND=true ;;
        --verbose|-v) VERBOSE=true ;;
        *) echo "Usage: $0 [--fail] [--verbose]" >&2; exit 1 ;;
    esac
    shift
done

echo "=== Secret Scanning Guardrail ==="
echo "Scanning: $REPO_ROOT"
echo "Mode: $FAIL_ON_FIND"
echo ""

TOTAL_ISSUES=0

# Secret patterns (POSIX extended regex)
scan_secrets() {
    local file="$1"

    # Skip binary files and certain directories
    case "$file" in
        *.pyc|*.so|*.dylib|*.dll|*.exe|*.bin) return ;;
        */node_modules/*|*/.git/*|*/.venv/*|*/venv/*|*/__pycache__/*) return ;;
        */.claude/*|*/.serena/*) return ;;
    esac

    # Read file line by line
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num+1))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Check for 1Password references (safe)
        [[ "$line" =~ op:// ]] && continue

        # Check for masked/placeholder values (safe)
        [[ "$line" =~ (placeholder|masked|example|xxx|TODO|REDACTED|\.\.\.|\.\*|your-.*-here|your-token|hardcoded-token-here) ]] && continue

        # Pattern 1: Hardcoded API keys/strings with common secret variable names
        # Updated: Detects tokens with . and - characters (e.g., 42d839...14a8um9X0PiC49iZ)
        if [[ "$line" =~ (export[[:space:]]+)?(ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|SLACK.*TOKEN|RAILWAY_TOKEN|API_KEY|SECRET_KEY|AUTH_TOKEN|PASSWORD|PASSWD|SECRET|BEARER|AUTHORIZATION)[[:space:]]*[:=]][[:space:]]*["'"'"'][A-Za-z0-9._/+=-]{15,}["'"'"'] ]]; then
            # Double-check it's not a safe placeholder
            if [[ ! "$line" =~ (placeholder|example|xxx|your-|hardcoded|REDACTED) ]]; then
                echo "🚨 HARD CODED SECRET FOUND:"
                echo "   File: $file"
                echo "   Line $line_num: $line"
                echo "$file:$line_num:$line" >> "$ISSUES_FILE"
                TOTAL_ISSUES=$((TOTAL_ISSUES+1))
                return
            fi
        fi

        # Pattern 2: Long Base64-like strings (32+ chars) - potential tokens
        # Updated: Detects tokens with . and - characters
        if [[ "$line" =~ ["'"'"'][A-Za-z0-9._/+=-]{32,}["'"'"'] ]] && [[ ! "$line" =~ (Bearer|ssh-r|BEGIN|-----|placeholder|example) ]]; then
            # Additional context check
            if [[ "$line" =~ (token|key|secret|auth|password|api|credential) ]]; then
                echo "🚨 POTENTIAL TOKEN STRING:"
                echo "   File: $file"
                echo "   Line $line_num: $line"
                echo "$file:$line_num:$line" >> "$ISSUES_FILE"
                TOTAL_ISSUES=$((TOTAL_ISSUES+1))
                return
            fi
        fi

        # Pattern 3: AWS keys
        if [[ "$line" =~ AKIA[0-9A-Z]{16} ]]; then
            echo "🚨 AWS ACCESS KEY:"
            echo "   File: $file"
            echo "   Line $line_num: $line"
            echo "$file:$line_num:$line" >> "$ISSUES_FILE"
            TOTAL_ISSUES=$((TOTAL_ISSUES+1))
            return
        fi

        # Pattern 4: GitHub/Slack tokens
        if [[ "$line" =~ (xox[b|p]-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9_]{36,}|gho_[A-Za-z0-9_]{36,}|ghu_[A-Za-z0-9_]{36,}|ghs_[A-Za-z0-9_]{36,}) ]]; then
            echo "🚨 GITHUB/SLACK TOKEN:"
            echo "   File: $file"
            echo "   Line $line_num: $line"
            echo "$file:$line_num:$line" >> "$ISSUES_FILE"
            TOTAL_ISSUES=$((TOTAL_ISSUES+1))
            return
        fi
    done < "$file"
}

# Scan all text files (use process substitution to avoid subshell counter loss)
while IFS= read -r file; do
    scan_secrets "$file"
done < <(find "$REPO_ROOT" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.md" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.pytest_cache/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/target/*" \
    -not -path "*/.claude/*" \
    -not -path "*/.serena/*" \
    -print 2>/dev/null)

# Report results
echo ""
if [[ $TOTAL_ISSUES -eq 0 ]]; then
    echo "✅ No secrets found (scan passed)"
    rm -f "$ISSUES_FILE"
    exit 0
else
    echo "❌ Found $TOTAL_ISSUES potential secret(s)"
    echo ""
    echo "Review required: $ISSUES_FILE"
    echo ""

    if [[ "$FAIL_ON_FIND" == "true" ]]; then
        echo "FAIL: Secret scan failed. Review and remove secrets before committing."
        echo ""
        echo "Common fixes:"
        echo "  1. Use 1Password: op run -- command"
        echo "  2. Load from env: os.environ.get('VAR_NAME')"
        echo "  3. Use op:// references in config files"
        echo "  4. Set via export/export-op in wrapper scripts"
        exit 1
    else
        echo "WARNING: Secret scan completed with issues. Review recommended."
        exit 0
    fi
fi
