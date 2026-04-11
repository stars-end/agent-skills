#!/bin/bash
# Legacy universal Agent Bootstrap & Health Check.
# Deprecated as a fresh-device bootstrap surface; see
# docs/FRESH_DEVICE_BOOTSTRAP_AUDIT.md for the active contract.
# Usage: curl -fsSL <URL> | bash

set -e

echo "🤖 Bootstrapping Agent Environment..."

# 1. Ensure agent-skills exists
if [ ! -d "$HOME/agent-skills" ]; then
    echo "📥 Cloning agent-skills..."
    git clone https://github.com/stars-end/agent-skills.git "$HOME/agent-skills"
else
    echo "🔄 Updating agent-skills..."
    cd "$HOME/agent-skills" && git pull origin master
fi

# 2. Hydrate & Link
"$HOME/agent-skills/scripts/dx-hydrate.sh"

# 3. Source env (for this shell)
source "$HOME/.bashrc" 2>/dev/null || true

# 4. Run Health Check
echo "🩺 Running DX Check..."
"$HOME/agent-skills/scripts/dx-check.sh"
