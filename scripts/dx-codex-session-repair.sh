#!/usr/bin/env bash
#
# dx-codex-session-repair.sh
#
# Backup-first Codex session JSONL scan/repair wrapper.
#
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${DX_CODEX_SESSION_REPAIR_STATE_DIR:-$HOME/.dx-state/codex-session-repair}"
REPORT_PATH="${DX_CODEX_SESSION_REPAIR_REPORT_PATH:-$STATE_DIR/last.json}"
BACKUP_ROOT="${DX_CODEX_SESSION_REPAIR_BACKUP_ROOT:-$HOME/.codex/session-repair-backups}"
RECENT_HOURS="${DX_CODEX_SESSION_REPAIR_RECENT_HOURS:-12}"
RETENTION_DAYS="${DX_CODEX_SESSION_REPAIR_RETENTION_DAYS:-30}"

mkdir -p "$STATE_DIR" "$(dirname "$REPORT_PATH")" "$BACKUP_ROOT"

exec python3 "$SCRIPT_DIR/dx-codex-session-repair.py" \
  --backup-root "$BACKUP_ROOT" \
  --recent-hours "$RECENT_HOURS" \
  --backup-retention-days "$RETENTION_DAYS" \
  --report-path "$REPORT_PATH" \
  "$@"
