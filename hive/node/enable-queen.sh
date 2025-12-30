#!/usr/bin/env bash
# hive/node/enable-queen.sh
# Installs and starts the Hive Queen systemd user service.

set -e

SERVICE_FILE="hive-queen.service"
SRC_PATH="$HOME/agent-skills/hive/node/$SERVICE_FILE"
DEST_DIR="$HOME/.config/systemd/user"
DEST_PATH="$DEST_DIR/$SERVICE_FILE"

echo "👑 Configuring Hive Queen Service..."

# 1. Ensure systemd user directory exists
mkdir -p "$DEST_DIR"

# 2. Link the service file
# We copy instead of symlink to avoid issues if the repo moves, 
# but symlinking allows updates to propagate immediately. 
# Let's symlink for dev velocity.
ln -sf "$SRC_PATH" "$DEST_PATH"
echo "   -> Linked $SERVICE_FILE to $DEST_DIR"

# 3. Reload Systemd
systemctl --user daemon-reload

# 4. Enable and Start
echo "   -> Enabling and Starting service..."
systemctl --user enable "$SERVICE_FILE"
systemctl --user restart "$SERVICE_FILE"

# 5. Verify
if systemctl --user is-active --quiet "$SERVICE_FILE"; then
    echo "✅ Hive Queen is RUNNING."
    echo "   View logs with: journalctl --user -u hive-queen -f"
else
    echo "❌ Hive Queen failed to start."
    systemctl --user status "$SERVICE_FILE"
fi
