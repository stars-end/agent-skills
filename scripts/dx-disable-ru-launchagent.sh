#!/usr/bin/env bash
# Disable legacy ru 15-minute LaunchAgent to reduce scheduler noise/drift.

set -euo pipefail

LABEL="${DX_RU_LAUNCHAGENT_LABEL:-io.agentskills.ru}"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
QUARANTINE_DIR="$HOME/.dx-disabled-launchagents"
DISABLED_PLIST="$QUARANTINE_DIR/${LABEL}.plist.disabled"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "No-op: ru LaunchAgent disable is macOS-only."
  exit 0
fi

mkdir -p "$QUARANTINE_DIR"

if launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
fi

if [[ -f "$PLIST" ]]; then
  mv "$PLIST" "$DISABLED_PLIST"
  echo "Disabled LaunchAgent: $LABEL"
  echo "Moved: $PLIST -> $DISABLED_PLIST"
else
  echo "LaunchAgent plist not present: $PLIST"
fi
