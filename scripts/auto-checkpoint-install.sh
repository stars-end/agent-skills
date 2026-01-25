#!/usr/bin/env bash
# auto-checkpoint-install.sh
# Install and schedule auto-checkpoint across Linux and macOS.
#
# Usage:
#   auto-checkpoint-install.sh [--uninstall]
#
# Scheduling:
# - Linux: systemd user timer
# - macOS: launchd agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_CHECKPOINT_SH="$SCRIPT_DIR/auto-checkpoint.sh"
LOG_DIR="${AUTO_CHECKPOINT_LOG_DIR:-$HOME/.auto-checkpoint}"

# ============================================================
# Detect OS
# ============================================================

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *)       echo "unknown" ;;
  esac
}

OS="$(detect_os)"

# ============================================================
# Linux (systemd) Installation
# ============================================================

install_systemd() {
  local user_dir="$HOME/.config/systemd/user"
  mkdir -p "$user_dir"

  # Create systemd service
  cat > "$user_dir/auto-checkpoint.service" <<EOF
[Unit]
Description=Auto-checkpoint for agent sessions
Documentation=file://$SCRIPT_DIR/auto-checkpoint.sh

[Service]
Type=oneshot
ExecStart=$AUTO_CHECKPOINT_SH
Nice=10
IOSchedulingClass=idle
IOSchedulingPriority=7

# Safety: limit runtime
TimeoutStartSec=600
EOF

  # Create systemd timer (run every 15 minutes)
  cat > "$user_dir/auto-checkpoint.timer" <<EOF
[Unit]
Description=Auto-checkpoint timer (every 15 min)
Requires=auto-checkpoint.service

[Timer]
OnCalendar=*:0/15
OnBootSec=5min
AccuracySec=1m

[Install]
WantedBy=timers.target
EOF

  # Reload and enable
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable auto-checkpoint.timer 2>/dev/null || true
  systemctl --user start auto-checkpoint.timer 2>/dev/null || true

  echo "✅ Installed auto-checkpoint systemd timer (runs every 15 min)"
  echo "   Check: systemctl --user status auto-checkpoint.timer"
  echo "   Logs: journalctl --user -u auto-checkpoint"
}

uninstall_systemd() {
  local user_dir="$HOME/.config/systemd/user"

  systemctl --user stop auto-checkpoint.timer 2>/dev/null || true
  systemctl --user disable auto-checkpoint.timer 2>/dev/null || true
  rm -f "$user_dir/auto-checkpoint.service" "$user_dir/auto-checkpoint.timer"
  systemctl --user daemon-reload 2>/dev/null || true

  echo "✅ Uninstalled auto-checkpoint systemd timer"
}

# ============================================================
# macOS (launchd) Installation
# ============================================================

install_launchd() {
  local plist_label="com.agent-skills.auto-checkpoint"
  local plist_file="$HOME/Library/LaunchAgents/$plist_label.plist"

  cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$plist_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$AUTO_CHECKPOINT_SH</string>
  </array>
  <key>StartInterval</key>
  <integer>900</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>Nice</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/checkpoint.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/checkpoint.err</string>
</dict>
</plist>
EOF

  # Load the agent
  launchctl load "$plist_file" 2>/dev/null || true

  echo "✅ Installed auto-checkpoint launchd agent (runs every 15 min)"
  echo "   Check: launchctl list | grep auto-checkpoint"
  echo "   Logs: $LOG_DIR/checkpoint.log"
}

uninstall_launchd() {
  local plist_label="com.agent-skills.auto-checkpoint"
  local plist_file="$HOME/Library/LaunchAgents/$plist_label.plist"

  launchctl unload "$plist_file" 2>/dev/null || true
  rm -f "$plist_file"

  echo "✅ Uninstalled auto-checkpoint launchd agent"
}

# ============================================================
# Manual Run
# ============================================================

run_now() {
  echo "Running auto-checkpoint now..."
  "$AUTO_CHECKPOINT_SH"
}

# ============================================================
# Status Check
# ============================================================

status() {
  echo "--- Auto-checkpoint Status ---"
  echo "Script: $AUTO_CHECKPOINT_SH"
  echo "Log dir: $LOG_DIR"

  if [ -f "$LOG_DIR/last-run" ]; then
    local last_run_ts
    last_run_ts=$(cat "$LOG_DIR/last-run")
    local last_run
    last_run=$(date -d "@$last_run_ts" 2>/dev/null || date -r "$last_run_ts" 2>/dev/null || echo "unknown")
    echo "Last run: $last_run"
  else
    echo "Last run: never"
  fi

  case "$OS" in
    linux)
      if systemctl --user is-active auto-checkpoint.timer >/dev/null 2>&1; then
        echo "Scheduler: systemd (active)"
      else
        echo "Scheduler: systemd (inactive or not installed)"
      fi
      ;;
    macos)
      if launchctl list 2>/dev/null | grep -q "auto-checkpoint"; then
        echo "Scheduler: launchd (active)"
      else
        echo "Scheduler: launchd (inactive or not installed)"
      fi
      ;;
  esac
}

# ============================================================
# Main
# ============================================================

UNINSTALL=0
RUN_NOW=0
SHOW_STATUS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --run)
      RUN_NOW=1
      shift
      ;;
    --status)
      SHOW_STATUS=1
      shift
      ;;
    *)
      echo "Usage: $0 [--uninstall] [--run] [--status]" >&2
      exit 1
      ;;
  esac
done

# Ensure script exists
if [ ! -f "$AUTO_CHECKPOINT_SH" ]; then
  echo "Error: auto-checkpoint.sh not found at $AUTO_CHECKPOINT_SH" >&2
  exit 1
fi

# Ensure log directory
mkdir -p "$LOG_DIR"

if [ $SHOW_STATUS -eq 1 ]; then
  status
  exit 0
fi

if [ $RUN_NOW -eq 1 ]; then
  run_now
  exit 0
fi

if [ $UNINSTALL -eq 1 ]; then
  case "$OS" in
    linux)   uninstall_systemd ;;
    macos)   uninstall_launchd ;;
    *)       echo "Unknown OS: $OS" >&2 ; exit 1 ;;
  esac
  exit 0
fi

# Install
case "$OS" in
  linux)   install_systemd ;;
  macos)   install_launchd ;;
  *)       echo "Unknown OS: $OS" >&2 ; exit 1 ;;
esac
