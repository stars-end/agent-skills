#!/usr/bin/env bash
# bd-doctor fix - deterministic remediation for canonical ~/bd workflow

set -euo pipefail

BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
LOCK_FILE="$BEADS_REPO/.beads/.dx-bd-mutation.lock"
LOCK_DIR="${LOCK_FILE}.d"
HOST="${BEADS_DOLT_SERVER_HOST:-127.0.0.1}"
PORT="${BEADS_DOLT_SERVER_PORT:-${BEADS_DOLT_PORT:-3307}}"
DATA_DIR="$BEADS_REPO/.beads/dolt"
DB_REPO_DIR="$DATA_DIR/beads_bd"

echo "🔧 Beads Doctor Fix (canonical mode)"
echo "repo: $BEADS_REPO"
echo "server: ${HOST}:${PORT}"

if [[ ! -d "$BEADS_REPO/.git" ]]; then
  echo "❌ Canonical repo missing: $BEADS_REPO"
  exit 1
fi

cd "$BEADS_REPO"
mkdir -p "$BEADS_REPO/.beads"

acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -w 15 9 || {
      echo "❌ Could not acquire Beads lock: $LOCK_FILE"
      exit 1
    }
    return 0
  fi

  local i
  for _ in $(seq 1 15); do
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

is_local_target_host() {
  case "$HOST" in
    127.0.0.1|localhost|::1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_service_online() {
  local os
  if ! is_local_target_host; then
    echo "ℹ️  Spoke mode detected (${HOST}); skipping local service check"
    return 0
  fi

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
  local listen_host="${1:-127.0.0.1}"
  local pids
  pids=""

  if command -v lsof >/dev/null 2>&1; then
    if [[ "$listen_host" == "0.0.0.0" ]] || [[ "$listen_host" == "*" ]]; then
      lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u
      return 0
    fi

    pids="$(lsof -nP -t -iTCP@"${listen_host}:$PORT" -sTCP:LISTEN 2>/dev/null | sort -u || true)"
    if [[ -z "$pids" ]]; then
      lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u
      return 0
    fi
    echo "$pids"
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
  if ! is_local_target_host; then
    return 0
  fi

  mapfile -t pids < <(single_listener_pid "$HOST")
  if [[ "${#pids[@]}" -eq 0 ]]; then
    echo "❌ No process is listening on ${HOST}:${PORT}"
    echo "   run: systemctl --user restart beads-dolt.service (or launchctl on macOS)"
    exit 1
  fi

  if [[ "${#pids[@]}" -gt 1 ]]; then
    echo "❌ Multiple listeners detected on :$PORT: ${pids[*]}"
    echo "   stop unmanaged dolt/sql processes before remediation"
    exit 1
  fi

  local cmd
  cmd="$(ps -p "${pids[0]}" -o command= 2>/dev/null || true)"
  if [[ "$cmd" != *"dolt sql-server"* ]] || [[ "$cmd" != *"--data-dir"* ]] || [[ "$cmd" != *"$DATA_DIR"* ]]; then
    echo "❌ Listener on :$PORT is not the managed Beads dolt server"
    echo "   pid=${pids[0]} cmd=$cmd"
    echo "   expected: dolt sql-server --data-dir $DATA_DIR"
    exit 1
  fi

  echo "✅ Single managed listener verified on :$PORT (pid ${pids[0]})"
}

assert_remote_reachability() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    if nc -z -w 3 "$host" "$port"; then
      return 0
    fi
    echo "❌ Cannot reach Beads SQL endpoint ${host}:${port}"
    return 1
  fi

  local probe_cmd
  probe_cmd="exec 9<>/dev/tcp/${host}/${port}"
  if command -v timeout >/dev/null 2>&1; then
    if timeout 3 bash -c "$probe_cmd" >/dev/null 2>&1; then
      return 0
    fi
    echo "❌ Cannot reach Beads SQL endpoint ${host}:${port}"
    return 1
  fi

  if bash -c "$probe_cmd" >/dev/null 2>&1; then
    return 0
  fi
  echo "❌ Cannot reach Beads SQL endpoint ${host}:${port}"
  return 1
}

assert_server_connectivity() {
  if is_local_target_host; then
    assert_single_managed_listener
    return 0
  fi

  if ! assert_remote_reachability "$HOST" "$PORT"; then
    exit 1
  fi
  echo "✅ Beads endpoint reachable at ${HOST}:${PORT}"
}

if [[ -f ".beads/beads.db" && -f ".beads/bd.db" ]]; then
  backup=".beads/beads.db.backup.$(date +%Y%m%d%H%M%S)"
  mv ".beads/beads.db" "$backup"
  echo "✅ Archived legacy DB file: $backup"
fi

require_service_online
assert_server_connectivity

echo "Running canonical Dolt remote fast-forward pull..."
if is_local_target_host; then
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
else
  echo "✅ Spoke mode detected (BEADS_DOLT_SERVER_HOST=$HOST); skipping local Dolt repo pull checks"
fi

echo "Running bd doctor --fix (best effort)..."
bd doctor --fix >/dev/null 2>&1 || true

if bd doctor --json 2>/dev/null | grep -q '\"status\"[[:space:]]*:[[:space:]]*\"error\"'; then
  echo "❌ Remaining doctor errors detected"
  exit 1
fi

echo "✅ Beads remediation complete"
