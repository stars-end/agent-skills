#!/usr/bin/env bash
# auto-checkpoint-install.sh
# Install and schedule auto-checkpoint across Linux and macOS.
#
# Usage:
#   auto-checkpoint-install            # installs + enables scheduler
#   auto-checkpoint-install --status   # reports scheduler + last run
#   auto-checkpoint-install --status --check  # exits non-zero if scheduler inactive/missing
#   auto-checkpoint-install --run      # runs auto-checkpoint immediately
#   auto-checkpoint-install --uninstall # disables + removes scheduler

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_CHECKPOINT_BIN="$HOME/bin/auto-checkpoint"
LOG_DIR="${AUTO_CHECKPOINT_LOG_DIR:-$HOME/.auto-checkpoint}"
MAIN_LOG_DIR="$HOME/logs"
MAIN_LOG_FILE="$MAIN_LOG_DIR/auto-checkpoint.log"

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
# Build PATH with mise shims + brew paths
# ============================================================

build_safe_path() {
  local path=""
  # Standard paths
  path="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

  # mise shims (highest priority for correct tool versions)
  if [ -d "$HOME/.local/share/mise/shims" ]; then
    path="$HOME/.local/share/mise/shims:$path"
  fi

  # brew paths (macOS and Linux)
  if [ -d "/home/linuxbrew/.linuxbrew/bin" ]; then
    path="/home/linuxbrew/.linuxbrew/bin:$path"
  fi
  if [ -d "/opt/homebrew/bin" ]; then
    path="/opt/homebrew/bin:$path"
  fi
  if [ -d "/usr/local/bin" ]; then
    # Already included, but ensure priority
    path="/usr/local/bin:$path"
  fi

  echo "$path"
}

SAFE_PATH="$(build_safe_path)"

# ============================================================
# Linux (systemd) Installation
# ============================================================

install_systemd() {
  local user_dir="$HOME/.config/systemd/user"
  mkdir -p "$user_dir"

  # Create systemd service that calls auto-checkpoint for each canonical repo
  cat > "$user_dir/auto-checkpoint.service" <<EOF
[Unit]
Description=Auto-checkpoint for agent sessions
Documentation=file://$SCRIPT_DIR/auto-checkpoint.sh

[Service]
Type=oneshot
Environment="PATH=$SAFE_PATH"
ExecStart=$AUTO_CHECKPOINT_BIN
Nice=10
IOSchedulingClass=idle
IOSchedulingPriority=7

# Safety: limit runtime
TimeoutStartSec=600

# Append to main log file
StandardOutput=append:$MAIN_LOG_FILE
StandardError=append:$MAIN_LOG_FILE
EOF

  # Create systemd timer (run every 4 hours)
  cat > "$user_dir/auto-checkpoint.timer" <<EOF
[Unit]
Description=Auto-checkpoint timer (every 4 hours)
Requires=auto-checkpoint.service

[Timer]
OnCalendar=*:0/4
OnBootSec=5min
AccuracySec=1m

[Install]
WantedBy=timers.target
EOF

  # Create log directory
  mkdir -p "$MAIN_LOG_DIR"
  touch "$MAIN_LOG_FILE"

  # Reload and enable
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable auto-checkpoint.timer 2>/dev/null || true
  systemctl --user start auto-checkpoint.timer 2>/dev/null || true

  echo "✅ Installed auto-checkpoint systemd timer (runs every 4 hours)"
  echo "   Check: systemctl --user status auto-checkpoint.timer"
  echo "   Logs: $MAIN_LOG_FILE"
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
# Linux (crontab) Fallback
# ============================================================

install_crontab() {
  local cron_entry="0 */4 * * * PATH=$SAFE_PATH $AUTO_CHECKPOINT_BIN >> $MAIN_LOG_FILE 2>&1"

  # Remove existing entry
  crontab -l 2>/dev/null | grep -v "auto-checkpoint" | crontab - 2>/dev/null || true

  # Add new entry
  (crontab -l 2>/dev/null || true; echo "$cron_entry") | crontab -

  # Create log directory
  mkdir -p "$MAIN_LOG_DIR"
  touch "$MAIN_LOG_FILE"

  echo "✅ Installed auto-checkpoint crontab entry (runs every 4 hours)"
  echo "   Check: crontab -l | grep auto-checkpoint"
  echo "   Logs: $MAIN_LOG_FILE"
}

uninstall_crontab() {
  # Remove entry
  crontab -l 2>/dev/null | grep -v "auto-checkpoint" | crontab - 2>/dev/null || true
  echo "✅ Uninstalled auto-checkpoint crontab entry"
}

# ============================================================
# macOS (launchd) Installation
# ============================================================

install_launchd() {
  local plist_label="com.starsend.auto-checkpoint"
  local plist_file="$HOME/Library/LaunchAgents/$plist_label.plist"

  # Calculate interval: 4 hours = 14400 seconds
  cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$plist_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$AUTO_CHECKPOINT_BIN</string>
  </array>
  <key>StartInterval</key>
  <integer>14400</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>Nice</key>
  <integer>10</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$SAFE_PATH</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$MAIN_LOG_FILE</string>
  <key>StandardErrorPath</key>
  <string>$MAIN_LOG_FILE</string>
</dict>
</plist>
EOF

  # Create log directory
  mkdir -p "$MAIN_LOG_DIR"
  touch "$MAIN_LOG_FILE"

  # Bootstrap the agent (macOS Ventura+)
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootstrap "gui/$(id -u)" "$plist_file" 2>/dev/null || \
      launchctl load "$plist_file" 2>/dev/null || true
    launchctl enable "$plist_label" 2>/dev/null || true
  fi

  echo "✅ Installed auto-checkpoint launchd agent (runs every 4 hours)"
  echo "   Check: launchctl list | grep auto-checkpoint"
  echo "   Logs: $MAIN_LOG_FILE"
}

uninstall_launchd() {
  local plist_label="com.starsend.auto-checkpoint"
  local plist_file="$HOME/Library/LaunchAgents/$plist_label.plist"

  # Bootout the agent (macOS Ventura+)
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$plist_label" 2>/dev/null || \
      launchctl unload "$plist_file" 2>/dev/null || true
  fi

  rm -f "$plist_file"

  echo "✅ Uninstalled auto-checkpoint launchd agent"
}

# ============================================================
# Manual Run
# ============================================================

run_now() {
  echo "Running auto-checkpoint now..."
  if [ -f "$AUTO_CHECKPOINT_BIN" ]; then
    "$AUTO_CHECKPOINT_BIN"
  else
    echo "Error: $AUTO_CHECKPOINT_BIN not found" >&2
    echo "Run: scripts/dx-ensure-bins.sh" >&2
    exit 1
  fi
}

# ============================================================
# Status Check
# ============================================================

status() {
  local status_code=0

  echo "--- Auto-checkpoint Status ---"
  echo "Binary: $AUTO_CHECKPOINT_BIN"
  echo "Log dir: $LOG_DIR"
  echo "Main log: $MAIN_LOG_FILE"

  if [ ! -x "$AUTO_CHECKPOINT_BIN" ]; then
    status_code=3
  fi

  if [ -f "$LOG_DIR/last-run" ]; then
    last_run_ts=$(cat "$LOG_DIR/last-run")
    current_ts=$(date +%s)
    minutes_since=$(( (current_ts - last_run_ts) / 60 ))
    echo "Last run: ${minutes_since}m ago"
  else
    echo "Last run: never"
  fi

  case "$OS" in
    linux)
      # Check systemd first
      if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active auto-checkpoint.timer >/dev/null 2>&1; then
        echo "Scheduler: systemd (active)"
      elif command -v crontab >/dev/null 2>&1 && grep -q "auto-checkpoint" < <(crontab -l 2>/dev/null); then
        echo "Scheduler: crontab (active)"
      else
        echo "Scheduler: not installed"
        if [ $status_code -eq 0 ]; then
          status_code=2
        fi
      fi
      ;;
    macos)
      # Avoid pipefail + SIGPIPE false negatives from `... | grep -q ...`
      if grep -q "auto-checkpoint" < <(launchctl list 2>/dev/null); then
        echo "Scheduler: launchd (active)"
      else
        echo "Scheduler: not installed"
        if [ $status_code -eq 0 ]; then
          status_code=2
        fi
      fi
      ;;
    *)
      echo "Scheduler: unknown (unsupported OS)"
      status_code=4
      ;;
  esac

  AUTO_CHECKPOINT_STATUS_CODE="$status_code"
}

# ============================================================
# Main
# ============================================================

UNINSTALL=0
RUN_NOW=0
SHOW_STATUS=0
CHECK_ONLY=0

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
    --check)
      CHECK_ONLY=1
      shift
      ;;
    *)
      echo "Usage: $0 [--uninstall] [--run] [--status [--check]]" >&2
      exit 1
      ;;
  esac
done

# Ensure log directories
mkdir -p "$LOG_DIR"
mkdir -p "$MAIN_LOG_DIR"

if [ $SHOW_STATUS -eq 1 ]; then
  status
  if [ $CHECK_ONLY -eq 1 ]; then
    exit "${AUTO_CHECKPOINT_STATUS_CODE:-2}"
  fi
  exit 0
fi

if [ $RUN_NOW -eq 1 ]; then
  run_now
  exit 0
fi

if [ $UNINSTALL -eq 1 ]; then
  case "$OS" in
    linux)
      # Try systemd first, then crontab
      if systemctl --user is-active auto-checkpoint.timer >/dev/null 2>&1 2>/dev/null; then
        uninstall_systemd
      elif command -v crontab >/dev/null 2>&1 && grep -q "auto-checkpoint" < <(crontab -l 2>/dev/null); then
        uninstall_crontab
      else
        echo "Nothing to uninstall (no auto-checkpoint scheduler found)"
      fi
      ;;
    macos)
      uninstall_launchd
      ;;
    *)
      echo "Unknown OS: $OS" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# Install
case "$OS" in
  linux)
    # Prefer systemd; fallback to crontab if systemd --user is unavailable
    if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
      install_systemd
    else
      echo "systemd --user not available, using crontab fallback..."
      install_crontab
    fi
    ;;
  macos)
    install_launchd
    ;;
  *)
    echo "Unknown OS: $OS" >&2
    exit 1
    ;;
esac
