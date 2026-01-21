#!/bin/bash
set -euo pipefail

TARGET_VM="fengning@homedesktop-wsl"

echo "Updating ~/.claude.json on $TARGET_VM..."

# Create a temporary jq script
cat > jq_script.txt <<'EOF'
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
scp jq_script.txt "$TARGET_VM:~/jq_script.txt"

# Execute remote update
ssh "$TARGET_VM" '
  cp ~/.claude.json ~/.claude.json.backup
  jq -f ~/jq_script.txt ~/.claude.json > ~/.claude.json.new && mv ~/.claude.json.new ~/.claude.json
  rm ~/jq_script.txt
'

# Clean up local
rm jq_script.txt

echo "✅ Updated ~/.claude.json on $TARGET_VM"