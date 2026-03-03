#!/usr/bin/env bash
# bd-doctor fix - deterministic remediation for canonical ~/bd workflow
# V2: Hub-spoke architecture validation (bd-va5h)

set -euo pipefail

BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
LOCK_FILE="$BEADS_REPO/.beads/.dx-bd-mutation.lock"
PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
HUB_HOST="${BEADS_DOLT_SERVER_HOST:-}"
DATA_DIR="$BEADS_REPO/.beads/dolt"
DB_REPO_DIR="$DATA_DIR/beads_bd"

# Hub-spoke configuration
HUB_TAILSCALE_IP="100.107.173.83"
HUB_HOSTNAME="epyc12"
SPOKE_HOSTS="macmini homedesktop-wsl epyc6"

echo "🔧 Beads Doctor Fix V2 (hub-spoke mode)"
echo "repo: $BEADS_REPO"
echo "hub: $HUB_TAILSCALE_IP:$PORT"

if [[ ! -d "$BEADS_REPO/.git" ]]; then
  echo "❌ Canonical repo missing: $BEADS_REPO"
  exit 1
fi

cd "$BEADS_REPO"
mkdir -p "$BEADS_REPO/.beads"

detect_host_role() {
  local hostname
  hostname=$(hostname 2>/dev/null || echo "")
  
  if [[ "$hostname" == "$HUB_HOSTNAME" ]] || \
     [[ "$(hostname -f 2>/dev/null)" == *"$HUB_HOSTNAME"* ]]; then
    echo "hub"
    return 0
  fi
  
  # Check if we're listening on hub IP
  if command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -q "$HUB_TAILSCALE_IP:$PORT"; then
    echo "hub"
    return 0
  fi
  
  echo "spoke"
}

HOST_ROLE=$(detect_host_role)
echo "Detected role: $HOST_ROLE"

validate_hub_spoke_config() {
  echo ""
  echo "=== Validating hub-spoke configuration ==="
  
  if [[ "$HOST_ROLE" == "hub" ]]; then
    validate_hub_config
  else
    validate_spoke_config
  fi
}

validate_hub_config() {
  echo "Validating HUB configuration..."
  
  # Hub must have Dolt server listening on Tailscale IP
  if ! command -v ss &>/dev/null; then
    echo "⚠️  ss not available, skipping listener check"
    return 0
  fi
  
  local listeners
  listeners=$(ss -tlnp 2>/dev/null | grep ":$PORT" | wc -l)
  
  if [[ "$listeners" -eq 0 ]]; then
    echo "❌ No Dolt server listening on port $PORT"
    echo "   run: systemctl --user restart beads-dolt.service"
    exit 1
  fi
  
  # Verify binding to Tailscale IP
  if ss -tlnp 2>/dev/null | grep -q "$HUB_TAILSCALE_IP:$PORT"; then
    echo "✅ Hub listening on Tailscale IP: $HUB_TAILSCALE_IP:$PORT"
  else
    echo "⚠️  Hub not listening on Tailscale IP, checking localhost..."
    if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:$PORT"; then
      echo "⚠️  Hub listening on localhost only - may need reconfiguration"
      echo "   expected: --host $HUB_TAILSCALE_IP"
    fi
  fi
  
  # Hub should have data directory
  if [[ ! -d "$DATA_DIR" ]]; then
    echo "❌ Hub data directory missing: $DATA_DIR"
    exit 1
  fi
  echo "✅ Hub data directory exists: $DATA_DIR"
}

validate_spoke_config() {
  echo "Validating SPOKE configuration..."
  
  # Spokes should NOT have local Dolt server running
  if command -v ss &>/dev/null; then
    local local_listeners
    local_listeners=$(ss -tlnp 2>/dev/null | grep -E "127.0.0.1:$PORT|0.0.0.0:$PORT" | wc -l)
    
    if [[ "$local_listeners" -gt 0 ]]; then
      echo "❌ SPOKE has local Dolt server running - this violates hub-spoke architecture"
      echo "   Stop local service: systemctl --user stop beads-dolt.service"
      echo "   Spokes must connect to hub at $HUB_TAILSCALE_IP:$PORT"
      exit 1
    fi
    echo "✅ No local Dolt server (correct for spoke)"
  fi
  
  # Spokes must have BEADS_DOLT_SERVER_HOST set
  if [[ -z "$HUB_HOST" ]]; then
    echo "❌ BEADS_DOLT_SERVER_HOST not set"
    echo "   export BEADS_DOLT_SERVER_HOST=$HUB_TAILSCALE_IP"
    exit 1
  fi
  echo "✅ BEADS_DOLT_SERVER_HOST=$HUB_HOST"
  
  # Verify connectivity to hub
  echo "Testing connectivity to hub..."
  if ! timeout 10 bd dolt test --json 2>/dev/null | grep -q '"connection_ok": true'; then
    echo "❌ Cannot connect to hub at $HUB_HOST:$PORT"
    echo "   Check: tailscale ping $HUB_HOSTNAME"
    echo "   Check: systemctl --user status beads-dolt.service (on hub)"
    exit 1
  fi
  echo "✅ Connected to hub: $HUB_HOST:$PORT"
}

check_tailscale_connectivity() {
  if ! command -v tailscale &>/dev/null; then
    echo "⚠️  tailscale CLI not available"
    return 0
  fi
  
  echo ""
  echo "=== Tailscale connectivity ==="
  
  if tailscale status 2>/dev/null | grep -q "$HUB_HOSTNAME"; then
    echo "✅ Hub ($HUB_HOSTNAME) visible in Tailscale network"
  else
    echo "⚠️  Hub ($HUB_HOSTNAME) not visible in Tailscale status"
  fi
}

run_bd_doctor() {
  echo ""
  echo "=== Running bd doctor ==="
  
  if bd doctor --json 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"error"'; then
    echo "⚠️  bd doctor reports errors, attempting fix..."
    bd doctor --fix >/dev/null 2>&1 || true
  fi
  
  if bd dolt test --json 2>/dev/null | grep -q '"connection_ok": true'; then
    echo "✅ bd dolt test passed"
  else
    echo "❌ bd dolt test failed"
    exit 1
  fi
}

verify_issue_counts() {
  echo ""
  echo "=== Verifying data consistency ==="
  
  local local_count
  local_count=$(bd status --json 2>/dev/null | jq -r '.summary.total_issues' 2>/dev/null || echo "unknown")
  
  echo "Local issue count: $local_count"
  
  if [[ "$HOST_ROLE" == "spoke" ]]; then
    echo "ℹ️  Spoke mode: counts should match hub (single source of truth)"
  fi
}

deprecated_sync_check() {
  echo ""
  echo "=== Checking for deprecated sync patterns ==="
  
  local warnings=0
  
  # Check for dolt push/pull cron jobs
  if crontab -l 2>/dev/null | grep -qE "dolt (push|pull)"; then
    echo "⚠️  DEPRECATED: Found dolt push/pull in crontab"
    echo "   Hub-spoke mode does not use dolt push/pull between hosts"
    ((warnings++))
  fi
  
  # Check for beads_sync.sh
  if [[ -f "$BEADS_REPO/.beads/beads_sync.sh" ]]; then
    echo "⚠️  DEPRECATED: Found beads_sync.sh (historical only)"
    ((warnings++))
  fi
  
  # Check for legacy JSONL files
  if ls "$BEADS_REPO/.beads/"*.jsonl 1>/dev/null 2>&1; then
    echo "⚠️  DEPRECATED: Found JSONL files (historical only)"
    ((warnings++))
  fi
  
  if [[ $warnings -eq 0 ]]; then
    echo "✅ No deprecated sync patterns found"
  else
    echo "⚠️  Found $warnings deprecated pattern(s) - review and clean up"
  fi
}

main() {
  validate_hub_spoke_config
  check_tailscale_connectivity
  run_bd_doctor
  verify_issue_counts
  deprecated_sync_check
  
  echo ""
  echo "=== Summary ==="
  echo "Role: $HOST_ROLE"
  echo "Hub: $HUB_TAILSCALE_IP:$PORT"
  echo "✅ Beads remediation complete"
}

main "$@"
