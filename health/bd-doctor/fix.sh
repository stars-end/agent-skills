#!/usr/bin/env bash
# bd-doctor fix - deterministic remediation for canonical ~/bd workflow

set -euo pipefail

BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
LOCK_FILE="$BEADS_REPO/.beads/.dx-bd-mutation.lock"

echo "🔧 Beads Doctor Fix (canonical mode)"
echo "repo: $BEADS_REPO"

if [[ ! -d "$BEADS_REPO/.git" ]]; then
  echo "❌ Canonical repo missing: $BEADS_REPO"
  exit 1
fi

cd "$BEADS_REPO"
mkdir -p "$BEADS_REPO/.beads"

# Single-writer lock while remediating.
exec 9>"$LOCK_FILE"
flock -w 15 9 || {
  echo "❌ Could not acquire Beads lock: $LOCK_FILE"
  exit 1
}

if [[ -f ".beads/beads.db" && -f ".beads/bd.db" ]]; then
  backup=".beads/beads.db.backup.$(date +%Y%m%d%H%M%S)"
  mv ".beads/beads.db" "$backup"
  echo "✅ Archived legacy DB file: $backup"
fi

echo "Running bd doctor --fix (best effort)..."
bd doctor --fix >/dev/null 2>&1 || true

echo "Running safe import sync..."
if timeout 120 bd sync --import-only --json >/tmp/bd-doctor-fix-sync.json 2>/tmp/bd-doctor-fix-sync.err; then
  echo "✅ bd sync --import-only completed"
else
  echo "⚠️  bd sync --import-only failed/timed out"
  sed -n '1,80p' /tmp/bd-doctor-fix-sync.err || true
fi

if bd doctor --json 2>/dev/null | grep -q '"status":"error"'; then
  echo "❌ Remaining doctor errors detected"
  exit 1
fi

echo "✅ Beads remediation complete"
