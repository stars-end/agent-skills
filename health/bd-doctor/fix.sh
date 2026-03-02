#!/usr/bin/env bash
# bd-doctor fix - deterministic remediation for canonical ~/bd workflow

set -euo pipefail

BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
LOCK_FILE="$BEADS_REPO/.beads/.dx-bd-mutation.lock"
PORT="${BEADS_DOLT_PORT:-3307}"
DATA_DIR="$BEADS_REPO/.beads/dolt"
DB_REPO_DIR="$DATA_DIR/beads_bd"

echo "🔧 Beads Doctor Fix (canonical mode)"
echo "repo: $BEADS_REPO"

if [[ ! -d "$BEADS_REPO/.git" ]]; then
  echo "❌ Canonical repo missing: $BEADS_REPO"
  exit 1
fi

cd "$BEADS_REPO"
mkdir -p "$BEADS_REPO/.beads"

# Single-writer lock while remediating.
LOCK_DIR="${LOCK_FILE}.d"
acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -w 15 9 || {
      echo "❌ Could not acquire Beads lock: $LOCK_FILE"
      exit 1
    }
    return 0
  fi

  # Portable fallback for hosts without flock (e.g., macOS default userland).
  local i
  for i in $(seq 1 15); do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "❌ Could not acquire Beads lock dir: $LOCK_DIR"
  exit 1
}

release_lock() {
  if command -v flock >/dev/null 2>&1; then
    return 0
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap release_lock EXIT
acquire_lock

require_service_online() {
  local os
  os="$(uname -s)"
  if [[ "$os" == "Linux" ]] && command -v systemctl >/dev/null 2>&1; then
    if ! systemctl --user is-active --quiet beads-dolt.service; then
      echo "❌ beads-dolt.service is not active on Linux host"
      echo "   run: systemctl --user restart beads-dolt.service"
      exit 1
    fi
    return 0
  fi

  if [[ "$os" == "Darwin" ]] && command -v launchctl >/dev/null 2>&1; then
    if ! launchctl print "gui/$(id -u)/com.starsend.beads-dolt" 2>/dev/null | grep -q 'state = running'; then
      echo "❌ com.starsend.beads-dolt is not running on macOS host"
      echo "   run: launchctl kickstart -k gui/$(id -u)/com.starsend.beads-dolt"
      exit 1
    fi
    return 0
  fi

  echo "⚠️  Unable to verify managed service status for this host"
}

single_listener_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -t -iTCP@"127.0.0.1:$PORT" -sTCP:LISTEN 2>/dev/null | sort -u
    return 0
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :$PORT )" 2>/dev/null \
      | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
      | sort -u
    return 0
  fi

  echo "❌ Neither lsof nor ss is available to inspect listening processes"
  exit 1
}

assert_single_managed_listener() {
  mapfile -t pids < <(single_listener_pid)
  if [[ "${#pids[@]}" -eq 0 ]]; then
    echo "❌ No process is listening on 127.0.0.1:$PORT"
    echo "   run: bd dolt test --json and restart managed service"
    exit 1
  fi

  if [[ "${#pids[@]}" -gt 1 ]]; then
    echo "❌ Multiple listeners detected on :$PORT: ${pids[*]}"
    echo "   stop unmanaged dolt/sql processes before remediation"
    exit 1
  fi

  local cmd
  cmd="$(ps -p "${pids[0]}" -o command= 2>/dev/null || true)"
  if [[ "$cmd" != *"dolt sql-server"* ]] || [[ "$cmd" != *"--data-dir $DATA_DIR"* ]]; then
    echo "❌ Listener on :$PORT is not the managed Beads Dolt server"
    echo "   pid=${pids[0]} cmd=$cmd"
    echo "   expected: dolt sql-server --data-dir $DATA_DIR"
    exit 1
  fi

  echo "✅ Single managed listener verified on :$PORT (pid ${pids[0]})"
}

if [[ -f ".beads/beads.db" && -f ".beads/bd.db" ]]; then
  backup=".beads/beads.db.backup.$(date +%Y%m%d%H%M%S)"
  mv ".beads/beads.db" "$backup"
  echo "✅ Archived legacy DB file: $backup"
fi

require_service_online
assert_single_managed_listener

echo "Running bd doctor --fix (best effort)..."
bd doctor --fix >/dev/null 2>&1 || true

echo "Running canonical Dolt remote fast-forward pull..."
if [[ -d "$DB_REPO_DIR/.dolt" ]]; then
  if (cd "$DB_REPO_DIR" && dolt remote -v 2>/dev/null | grep -q '^origin '); then
    if ! timeout 120 bash -lc "cd \"$DB_REPO_DIR\" && dolt fetch origin"; then
      echo "❌ Dolt fetch origin failed/timed out"
      exit 1
    fi

    ahead_count="$(cd "$DB_REPO_DIR" && dolt log --oneline remotes/origin/main..main | wc -l | tr -d '[:space:]')"
    if [[ "${ahead_count:-0}" -gt 0 ]]; then
      echo "❌ Local Dolt branch is ahead of origin by $ahead_count commit(s)"
      echo "   run: cd \"$DB_REPO_DIR\" && dolt push origin main"
      echo "   aborting pull to avoid overwriting unpushed local state"
      exit 1
    fi

    if timeout 180 bash -lc "cd \"$DB_REPO_DIR\" && dolt pull origin main --ff-only"; then
      echo "✅ Dolt remote pull completed"
    else
      echo "❌ Dolt remote pull failed (non-fast-forward or connectivity issue)"
      exit 1
    fi
  else
    echo "⚠️  No Dolt origin remote configured in $DB_REPO_DIR; skipping pull"
  fi
else
  echo "❌ Missing Dolt database repo dir: $DB_REPO_DIR"
  exit 1
fi

if bd doctor --json 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"error"'; then
  echo "❌ Remaining doctor errors detected"
  exit 1
fi

assert_single_managed_listener

echo "✅ Beads remediation complete"
