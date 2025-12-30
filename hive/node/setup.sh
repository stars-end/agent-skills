#!/usr/bin/env bash
set -euo pipefail
mkdir -p ~/repos ~/.agent-hive /tmp/pods
chmod 700 /tmp/pods
echo '{"sessions": {}, "nodes": {}}' > ~/.agent-hive/ledger.json
echo "✅ Hive Node Setup Complete"
