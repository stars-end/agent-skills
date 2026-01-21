#!/bin/bash
set -euo pipefail

TARGET="fengning@macmini"

echo "=== Troubleshooting Mac Coordinator ==="

ssh "$TARGET" '
  echo "1. Checking plist file:"
  ls -l ~/Library/LaunchAgents/com.starsend.slack-coordinator.plist
  cat ~/Library/LaunchAgents/com.starsend.slack-coordinator.plist

  echo ""
  echo "2. Checking Python path:"
  if [ -f ~/agent-skills/slack-coordination/.venv/bin/python ]; then
      echo "✅ venv python found"
      ~/agent-skills/slack-coordination/.venv/bin/python --version
  else
      echo "❌ venv python MISSING"
  fi

  echo ""
  echo "3. Checking script path:"
  if [ -f ~/agent-skills/slack-coordination/slack-coordinator.py ]; then
      echo "✅ script found"
  else
      echo "❌ script MISSING"
  fi

  echo ""
  echo "4. Checking logs:"
  ls -l /tmp/slack-coordinator.* 2>/dev/null || echo "No logs in /tmp"
'
