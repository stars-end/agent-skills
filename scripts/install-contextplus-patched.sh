#!/usr/bin/env bash
# install-contextplus-patched.sh — Build and install a locally-patched contextplus
#
# Fetches upstream contextplus at a pinned SHA, applies the OpenRouter
# embeddings patch, builds, and writes install metadata for drift detection.
#
# Usage:
#   scripts/install-contextplus-patched.sh          # install/update
#   scripts/install-contextplus-patched.sh --check  # check if install is current
#   scripts/install-contextplus-patched.sh --clean  # remove installed build
#
# Env vars:
#   CONTEXTPLUS_PATCH_DIR  — override build directory (default: ~/.local/share/contextplus-patched)

set -euo pipefail

# --- Configuration ---
UPSTREAM_REPO="https://github.com/ForLoopCodes/contextplus.git"
UPSTREAM_SHA="d2f44d32cf14fbd258bd1f012be6bd626ae20361"
PATCH_FILE="$(cd "$(dirname "$0")/.." && pwd)/patches/contextplus-openrouter-embeddings.patch"
WORK_DIR="${CONTEXTPLUS_PATCH_DIR:-$HOME/.local/share/contextplus-patched}"
METADATA_FILE="$WORK_DIR/install-metadata.json"
ENTRYPOINT="$WORK_DIR/build/index.js"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[info]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# --- Check mode ---
# Reads install-metadata.json for deterministic drift detection.
# Verifies both upstream SHA and patch checksum.
# Does NOT rely on --version output (which may not exist or be stable).
if [[ "${1:-}" == "--check" ]]; then
    if [[ ! -f "$METADATA_FILE" ]]; then
        echo "not-installed"
        exit 1
    fi
    installed_sha="$(python3 -c "import json; print(json.load(open('$METADATA_FILE')).get('upstream_sha','none'))" 2>/dev/null || echo "none")"
    installed_checksum="$(python3 -c "import json; print(json.load(open('$METADATA_FILE')).get('patch_checksum','none'))" 2>/dev/null || echo "none")"
    current_checksum="$(shasum "$PATCH_FILE" 2>/dev/null | cut -d' ' -f1 || echo "none")"

    if [[ "$installed_sha" != "$UPSTREAM_SHA" ]]; then
        echo "outdated (installed=${installed_sha:0:12}, want=${UPSTREAM_SHA:0:12})"
        exit 1
    fi
    if [[ "$installed_checksum" != "$current_checksum" ]]; then
        echo "patch-drift (installed=${installed_checksum:0:12}, current=${current_checksum:0:12})"
        exit 1
    fi
    echo "current (sha=${UPSTREAM_SHA:0:12}, checksum=${current_checksum:0:12})"
    exit 0
fi

# --- Clean mode ---
if [[ "${1:-}" == "--clean" ]]; then
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
        info "Removed build directory: $WORK_DIR"
    else
        warn "Nothing to remove at $WORK_DIR"
    fi
    exit 0
fi

# --- Pre-flight ---
if ! command -v node &>/dev/null; then
    error "node is required but not found in PATH"
fi
if ! command -v npm &>/dev/null; then
    error "npm is required but not found in PATH"
fi
if [[ ! -f "$PATCH_FILE" ]]; then
    error "Patch file not found: $PATCH_FILE"
fi

# --- Clone or update ---
if [[ -d "$WORK_DIR/.git" ]]; then
    info "Updating existing checkout at $WORK_DIR"
    cd "$WORK_DIR"
    git fetch origin main --depth=50 2>/dev/null
    git checkout "origin/main" 2>/dev/null
else
    info "Cloning upstream contextplus to $WORK_DIR"
    mkdir -p "$(dirname "$WORK_DIR")"
    git clone --depth 50 "$UPSTREAM_REPO" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Verify we have the right base — FAIL LOUD if pinned SHA is unavailable
current_sha="$(git rev-parse HEAD)"
if [[ "$current_sha" == "$UPSTREAM_SHA" ]]; then
    info "Already at pinned SHA $UPSTREAM_SHA"
else
    # If full history isn't available, fetch it
    if ! git cat-file -t "$UPSTREAM_SHA" &>/dev/null; then
        git fetch --unshallow 2>/dev/null || true
    fi
    if git cat-file -t "$UPSTREAM_SHA" &>/dev/null; then
        git reset --hard "$UPSTREAM_SHA"
        info "Reset to pinned SHA $UPSTREAM_SHA"
    else
        error "Pinned SHA $UPSTREAM_SHA not found in upstream. Aborting — will not silently drift to latest main."
    fi
fi

# --- Apply patch ---
info "Applying OpenRouter embeddings patch..."
# Check if patch is already applied
if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    info "Patch already applied, skipping"
else
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        info "Patch applied successfully"
    else
        error "Patch does not apply cleanly. Patch may need updating for new upstream version."
    fi
fi

# --- Install deps and build ---
info "Installing dependencies..."
npm install --no-fund --no-audit 2>/dev/null

info "Building..."
npm run build 2>/dev/null

if [[ ! -f "build/index.js" ]]; then
    error "Build failed — build/index.js not found"
fi

# --- Write install metadata ---
# Deterministic drift check: records SHA, patch checksum, and timestamp
patch_sha="$(shasum "$PATCH_FILE" | cut -d' ' -f1)"
python3 -c "
import json, datetime
meta = {
    'upstream_sha': '$UPSTREAM_SHA',
    'patch_checksum': '$patch_sha',
    'patch_file': '$PATCH_FILE',
    'installed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'entrypoint': '$ENTRYPOINT',
}
json.dump(meta, open('$METADATA_FILE', 'w'), indent=2)
" 2>/dev/null || warn "Could not write install metadata (python3 not available)"

chmod +x "$ENTRYPOINT"

# --- Summary ---
info "Installed contextplus-patched"
info "  Build dir:  $WORK_DIR"
info "  Entrypoint: $ENTRYPOINT"
info "  Upstream:   $(git rev-parse --short HEAD)"
info "  Metadata:   $METADATA_FILE"
info ""
info "MCP config should use: node $ENTRYPOINT"
info "Health check: test -f $ENTRYPOINT"
info "Drift check:  $0 --check"
info "Remove:        $0 --clean"
