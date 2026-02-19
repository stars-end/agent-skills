#!/bin/bash
# dx-eodhd-monitor.sh - Local EODHD API Health Monitor
# Migrated from GHA (monitor-eodhd.yml)

set -euo pipefail

# Setup environment
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

LOG_FILE="${HOME}/logs/dx-eodhd.log"
mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting EODHD health check..."

URL="https://backend-dev-6dd5.up.railway.app/api/v2/system/health/eodhd"
JSON_OUT="/tmp/eodhd_status.json"

HTTP_CODE=$(curl -s -k -o "$JSON_OUT" -w "%{http_code}" "$URL")

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ EODHD Health Check failed (HTTP $HTTP_CODE)"
    exit 1
fi

STATUS=$(jq -r '.status' "$JSON_OUT")
REASON=$(jq -r '.reason // "Unknown"' "$JSON_OUT")

if [ "$STATUS" == "unhealthy" ]; then
    echo "❌ EODHD Health Check UNHEALTHY: $REASON"
    exit 1
fi

echo "✅ EODHD Health OK"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] EODHD health check complete"
