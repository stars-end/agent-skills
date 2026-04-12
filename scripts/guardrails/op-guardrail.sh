#!/usr/bin/env bash
# 1Password CLI Guardrail for agent-skills and prime-radiant-ai
# Detects dangerous op CLI usage patterns and version mismatches
# Usage: scripts/guardrails/op-guardrail.sh [--fail] [--verbose]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERBOSE="${VERBOSE:-false}"
FAIL_ON_FIND="${FAIL_ON_FIND:-false}"
SKIP_OP_CLI_CHECK="${OP_GUARDRAIL_SKIP_CLI_CHECK:-false}"
ISSUES_FILE="/tmp/op-guardrail-issues.$$"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fail) FAIL_ON_FIND=true ;;
        --verbose|-v) VERBOSE=true ;;
        *) echo "Usage: $0 [--fail] [--verbose]" >&2; exit 1 ;;
    esac
    shift
done

echo "=== 1Password CLI Guardrail ==="
echo "Scanning: $REPO_ROOT"
echo "Mode: $FAIL_ON_FIND"
echo ""

TOTAL_ISSUES=0

# ============================================================
# Guard 1: Check op CLI Version
# ============================================================

echo "[1/5] Checking op CLI version..."
if [[ "$SKIP_OP_CLI_CHECK" == "true" ]]; then
    echo "↪ Skipped op CLI version check (OP_GUARDRAIL_SKIP_CLI_CHECK=true)"
else
    if command -v op >/dev/null 2>&1; then
        OP_VERSION=$(op --version 2>/dev/null || echo "0.0.0")
        REQUIRED="2.18.0"

        if [[ "$(printf '%s\n' "$REQUIRED" "$OP_VERSION" | sort -V | head -n1)" != "$REQUIRED" ]]; then
            echo "❌ GUARD: op CLI version $OP_VERSION < $REQUIRED (required for service accounts)"
            echo "   Action: brew upgrade op"
            echo "op_version:$OP_VERSION" >> "$ISSUES_FILE"
            TOTAL_ISSUES=$((TOTAL_ISSUES+1))
        else
            echo "✅ op CLI version: $OP_VERSION"
        fi
    else
        echo "❌ GUARD: op CLI not found"
        echo "   Action: brew install 1password-cli"
        echo "op_version:not_found" >> "$ISSUES_FILE"
        TOTAL_ISSUES=$((TOTAL_ISSUES+1))
    fi
fi

# ============================================================
# Guard 2: Detect OP_RUN_NO_MASKING
# ============================================================

echo ""
echo "[2/5] Scanning for --no-masking flag..."

NO_MASKING_FOUND=0
while IFS= read -r file; do
    case "$file" in
        *.pyc|*.so|*.dylib|*.dll|*.exe|*.bin) continue ;;
        */guardrails/*) continue ;;  # Skip guardrail scripts themselves (contain docs with examples)
    esac

    # Look for actual usage (in code), not documentation/comments
    # Match: op run --no-masking (as command, not in comment)
    if grep -E "^\s*op\s+run.*--no-masking" "$file" >/dev/null 2>&1; then
        echo "🚨 GUARD VIOLATION: --no-masking flag found (exposes secrets in output)"
        echo "   File: $file"
        echo "$file:--no-masking" >> "$ISSUES_FILE"
        TOTAL_ISSUES=$((TOTAL_ISSUES+1))
        NO_MASKING_FOUND=$((NO_MASKING_FOUND+1))
    fi
done < <(find "$REPO_ROOT" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" -o -name "*.yml" -o -name "*.yaml" \) \
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

if [[ $NO_MASKING_FOUND -eq 0 ]]; then
    echo "✅ No --no-masking usage found"
fi

# ============================================================
# Guard 3: Detect OP_CONNECT_* Environment Variables
# ============================================================

echo ""
echo "[3/5] Scanning for OP_CONNECT_* variables..."

OP_CONNECT_FOUND=0
# Check shell startup files
for shell_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
    if [[ -f "$shell_file" ]]; then
        if grep -q "OP_CONNECT_" "$shell_file" 2>/dev/null; then
            echo "🚨 GUARD VIOLATION: OP_CONNECT_* environment variable found"
            echo "   File: $shell_file"
            echo "   Issue: OP_CONNECT_* is for 1Password Connect server, not CLI"
            echo "   Fix: Use service account token (OP_SERVICE_ACCOUNT_TOKEN)"
            echo "$shell_file:OP_CONNECT_" >> "$ISSUES_FILE"
            TOTAL_ISSUES=$((TOTAL_ISSUES+1))
            OP_CONNECT_FOUND=$((OP_CONNECT_FOUND+1))
        fi
    fi
done

# Check scripts (exclude guardrails directory - it contains docs with these patterns)
while IFS= read -r file; do
    case "$file" in
        *.pyc|*.so|*.dylib|*.dll|*.exe|*.bin) continue ;;
        */guardrails/*) continue ;;  # Skip guardrail scripts (contain error messages with examples)
    esac

    if grep -q "OP_CONNECT_" "$file" 2>/dev/null; then
        echo "🚨 GUARD VIOLATION: OP_CONNECT_* variable found"
        echo "   File: $file"
        echo "$file:OP_CONNECT_" >> "$ISSUES_FILE"
        TOTAL_ISSUES=$((TOTAL_ISSUES+1))
        OP_CONNECT_FOUND=$((OP_CONNECT_FOUND+1))
    fi
done < <(find "$REPO_ROOT" -type f \( -name "*.py" -o -name "*.sh" -o -name "*.yml" -o -name "*.yaml" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.pytest_cache/*" \
    -not -path "*/.claude/*" \
    -not -path "*/.serena/*" \
    -not -path "*/guardrails/*" \
    -print 2>/dev/null)

if [[ $OP_CONNECT_FOUND -eq 0 ]]; then
    echo "✅ No OP_CONNECT_* usage found"
fi

# ============================================================
# Guard 4: Verify Service Account Token Usage
# ============================================================

echo ""
echo "[4/5] Verifying service account token patterns..."

HARDCODED_TOKENS=0
while IFS= read -r file; do
    case "$file" in
        *.pyc|*.so|*.dylib|*.dll|*.exe|*.bin) continue ;;
    esac

    # Check for hardcoded ops_* tokens in quotes
    if grep -qE "(OP_SERVICE_ACCOUNT_TOKEN|op_token)[[:space:]]*[:=][[:space:]]*['\"]ops_[A-Za-z0-9_-]{20,}" "$file" 2>/dev/null; then
        # Skip if it's an op:// reference (safe)
        if grep -v "op://" "$file" | grep -qE "(OP_SERVICE_ACCOUNT_TOKEN|op_token)[[:space:]]*[:=][[:space:]]*['\"]ops_[A-Za-z0-9_-]{20,}" 2>/dev/null; then
            echo "🚨 GUARD VIOLATION: Hardcoded service account token"
            echo "   File: $file"
            echo "$file:hardcoded_token" >> "$ISSUES_FILE"
            TOTAL_ISSUES=$((TOTAL_ISSUES+1))
            HARDCODED_TOKENS=$((HARDCODED_TOKENS+1))
        fi
    fi
done < <(find "$REPO_ROOT" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.pytest_cache/*" \
    -not -path "*/.claude/*" \
    -not -path "*/.serena/*" \
    -print 2>/dev/null)

if [[ $HARDCODED_TOKENS -eq 0 ]]; then
    echo "✅ No hardcoded service account tokens found"
fi

# ============================================================
# Guard 5: Reject raw OP commands in delegation/baseline surfaces
# ============================================================

echo ""
echo "[5/5] Scanning delegation/baseline surfaces for raw OP command snippets..."

RAW_OP_DOC_ISSUES=0
while IFS= read -r file; do
    # only command-like usage (line starts with op ...) to avoid prose mentions
    while IFS= read -r match; do
        line_no="${match%%:*}"
        line_text="${match#*:}"
        start=$((line_no>6 ? line_no-6 : 1))
        context="$(sed -n "${start},${line_no}p" "$file" | tr '[:upper:]' '[:lower:]')"
        if echo "$context" | grep -Eq "human fallback only|human recovery only|interactive auth \(human fallback only\)|manual bootstrap"; then
            continue
        fi
        echo "🚨 GUARD VIOLATION: raw OP command snippet in delegation/baseline surface"
        echo "   File: $file:$line_no"
        echo "   Line: $line_text"
        echo "$file:$line_no:raw_op_doc_surface" >> "$ISSUES_FILE"
        TOTAL_ISSUES=$((TOTAL_ISSUES+1))
        RAW_OP_DOC_ISSUES=$((RAW_OP_DOC_ISSUES+1))
    done < <(grep -nE '^[[:space:]]*op[[:space:]]+(read|whoami|item[[:space:]]+(get|list))\b' "$file" || true)
done < <(printf '%s\n' \
    "$REPO_ROOT/extended/prompt-writing/SKILL.md" \
    "$REPO_ROOT/scripts/publish-baseline.zsh" \
    "$REPO_ROOT/dist/universal-baseline.md")

if [[ $RAW_OP_DOC_ISSUES -eq 0 ]]; then
    echo "✅ No forbidden raw OP command snippets found in delegation/baseline surfaces"
fi

# ============================================================
# Report Results
# ============================================================

echo ""
if [[ $TOTAL_ISSUES -eq 0 ]]; then
    echo "✅ All op CLI guardrails passed"
    rm -f "$ISSUES_FILE"
    exit 0
else
    echo "❌ Found $TOTAL_ISSUES guardrail violation(s)"
    echo ""
    echo "Review required: $ISSUES_FILE"
    echo ""

    if [[ "$FAIL_ON_FIND" == "true" ]]; then
        echo "FAIL: op CLI guardrail failed. Review and fix violations before committing."
        echo ""
        echo "Common fixes:"
        echo "  1. Remove --no-masking flag from 'op run' commands"
        echo "  2. Replace OP_CONNECT_* with OP_SERVICE_ACCOUNT_TOKEN"
        echo "  3. Upgrade op CLI: brew upgrade op"
        echo "  4. Use LoadCredentialEncrypted for service account tokens"
        exit 1
    else
        echo "WARNING: op CLI guardrail completed with issues. Review recommended."
        exit 0
    fi
fi
