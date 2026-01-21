#!/bin/bash
set -euo pipefail

TARGET_VM="fengning@macmini"

echo "Updating ~/.claude.json on $TARGET_VM..."

# Create a temporary jq script
cat > jq_script_mac.txt <<'EOF'
.mcpServers.slack = {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-slack"],
  "env": {
    "SLACK_BOT_TOKEN": "${SLACK_BOT_TOKEN}",
    "SLACK_TEAM_ID": "T09LZQCF7KN"
  }
}
EOF

# Copy script to remote
scp jq_script_mac.txt "$TARGET_VM:~/jq_script.txt"

# Execute remote update
ssh "$TARGET_VM" '
  if [ -f ~/.claude.json ]; then
      cp ~/.claude.json ~/.claude.json.backup
      if command -v jq >/dev/null; then
          jq -f ~/jq_script.txt ~/.claude.json > ~/.claude.json.new && mv ~/.claude.json.new ~/.claude.json
      else
          echo "Warning: jq not found on macmini, skipping config update"
      fi
  else
      echo "Warning: ~/.claude.json not found on macmini"
  fi
  rm ~/jq_script.txt
'

# Clean up local
rm jq_script_mac.txt

echo "✅ Updated ~/.claude.json on $TARGET_VM (if present)"
