#!/usr/bin/env bash
set -euo pipefail

STATE_DB="${CODEX_STATE_DB:-$HOME/.codex/state_5.sqlite}"
TARGET_CWD="${1:-$(pwd)}"
MAX_AGE_HOURS="${DX_CODEX_THREAD_MAX_AGE_HOURS:-24}"

if [[ ! -f "$STATE_DB" ]]; then
  python3 - <<'PY' "$STATE_DB" "$TARGET_CWD"
import json, sys
print(json.dumps({"status": "skip", "reason": "state_db_missing", "state_db": sys.argv[1], "cwd": sys.argv[2]}))
PY
  exit 0
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  python3 - <<'PY' "$STATE_DB" "$TARGET_CWD"
import json, sys
print(json.dumps({"status": "skip", "reason": "sqlite3_missing", "state_db": sys.argv[1], "cwd": sys.argv[2]}))
PY
  exit 0
fi

python3 - <<'PY' "$STATE_DB" "$TARGET_CWD" "$MAX_AGE_HOURS"
import json
import sqlite3
import sys
from datetime import datetime, timezone

db_path, cwd, max_age_hours = sys.argv[1], sys.argv[2], int(sys.argv[3])
required = ["llm-tldr", "serena"]

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute(
        """
        SELECT id, updated_at
        FROM threads
        WHERE cwd = ?
        ORDER BY updated_at DESC
        LIMIT 1
        """,
        (cwd,),
    )
    row = cur.fetchone()
    if not row:
        print(json.dumps({
            "status": "skip",
            "reason": "no_thread_for_cwd",
            "state_db": db_path,
            "cwd": cwd,
            "required": required,
        }))
        raise SystemExit(0)

    thread_id, updated_at = row
    now = int(datetime.now(timezone.utc).timestamp())
    age_seconds = max(0, now - int(updated_at))
    age_hours = age_seconds / 3600.0

    if age_hours > max_age_hours:
        print(json.dumps({
            "status": "skip",
            "reason": "thread_too_old",
            "state_db": db_path,
            "cwd": cwd,
            "thread_id": thread_id,
            "thread_age_hours": round(age_hours, 2),
            "required": required,
        }))
        raise SystemExit(0)

    cur.execute(
        """
        SELECT name
        FROM thread_dynamic_tools
        WHERE thread_id = ?
        ORDER BY position ASC
        """,
        (thread_id,),
    )
    observed = [r[0] for r in cur.fetchall()]
    missing = [name for name in required if name not in observed]

    print(json.dumps({
        "status": "pass" if not missing else "fail",
        "reason": "all_required_tools_present" if not missing else "missing_required_thread_tools",
        "state_db": db_path,
        "cwd": cwd,
        "thread_id": thread_id,
        "thread_age_hours": round(age_hours, 2),
        "required": required,
        "observed": observed,
        "missing": missing,
    }))
except sqlite3.Error as exc:
    print(json.dumps({
        "status": "skip",
        "reason": "sqlite_error",
        "state_db": db_path,
        "cwd": cwd,
        "error": str(exc),
        "required": required,
    }))
PY
