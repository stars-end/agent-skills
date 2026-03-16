#!/usr/bin/env bash
# install-contextplus-patched.sh — Build and install a locally-patched contextplus
#
# Fetches upstream contextplus at a pinned SHA, applies the OpenRouter
# embeddings patch, builds, and symlinks the binary to ~/.local/bin.
#
# Usage:
#   scripts/install-contextplus-patched.sh          # install/update
#   scripts/install-contextplus-patched.sh --check  # check if install is current
#   scripts/install-contextplus-patched.sh --clean  # remove installed binary
#
# Env vars:
#   CONTEXTPLUS_PATCH_DIR  — override working directory (default: /tmp/contextplus-patched)
#   CONTEXTPLUS_INSTALL_DIR — override install target (default: ~/.local)

set -euo pipefail

# --- Configuration ---
UPSTREAM_REPO="https://github.com/ForLoopCodes/contextplus.git"
UPSTREAM_SHA="d2f44d32cf14fbd258bd1f012be6bd626ae20361"
PATCH_FILE="$(cd "$(dirname "$0")/.." && pwd)/patches/contextplus-openrouter-embeddings.patch"
WORK_DIR="${CONTEXTPLUS_PATCH_DIR:-/tmp/contextplus-patched}"
INSTALL_DIR="${CONTEXTPLUS_INSTALL_DIR:-$HOME/.local}"
BIN_NAME="contextplus"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[info]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# --- Check mode ---
if [[ "${1:-}" == "--check" ]]; then
    installed_sha="$("${INSTALL_DIR}/bin/${BIN_NAME}" --version 2>/dev/null | grep -o 'sha:[a-f0-9]*' | cut -d: -f2 || echo "none")"
    if [[ "$installed_sha" == "$UPSTREAM_SHA" ]]; then
        echo "current (${UPSTREAM_SHA:0:12})"
        exit 0
    else
        echo "outdated (installed=${installed_sha:0:12}, want=${UPSTREAM_SHA:0:12})"
        exit 1
    fi
fi

# --- Clean mode ---
if [[ "${1:-}" == "--clean" ]]; then
    target="${INSTALL_DIR}/bin/${BIN_NAME}"
    if [[ -L "$target" ]]; then
        rm "$target"
        info "Removed symlink: $target"
    elif [[ -f "$target" ]]; then
        rm "$target"
        info "Removed binary: $target"
    else
        warn "Nothing to remove at $target"
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
if ! mkdir -p "$INSTALL_DIR/bin" 2>/dev/null; then
    error "Cannot create $INSTALL_DIR/bin"
fi

# --- Clone or update ---
if [[ -d "$WORK_DIR/.git" ]]; then
    info "Updating existing checkout at $WORK_DIR"
    cd "$WORK_DIR"
    git fetch origin main --depth=50 2>/dev/null
    git checkout "origin/main" 2>/dev/null
else
    info "Cloning upstream contextplus to $WORK_DIR"
    git clone --depth 50 "$UPSTREAM_REPO" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Verify we have the right base
current_sha="$(git rev-parse HEAD)"
if [[ "$current_sha" != "$UPSTREAM_SHA" ]]; then
    warn "Current HEAD ($current_sha) differs from pinned SHA ($UPSTREAM_SHA)"
    warn "Attempting to reset to pinned version..."
    # If full history isn't available, fetch it
    if ! git cat-file -t "$UPSTREAM_SHA" &>/dev/null; then
        git fetch --unshallow 2>/dev/null || true
    fi
    if git cat-file -t "$UPSTREAM_SHA" &>/dev/null; then
        git reset --hard "$UPSTREAM_SHA"
        info "Reset to pinned SHA $UPSTREAM_SHA"
    else
        warn "Cannot find pinned SHA $UPSTREAM_SHA — installing from latest fetched main"
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

# --- Install binary ---
info "Installing to ${INSTALL_DIR}/bin/${BIN_NAME}"
# Remove old link if exists
rm -f "${INSTALL_DIR}/bin/${BIN_NAME}"

# Create symlink to the build entry point
ln -s "$WORK_DIR/build/index.js" "${INSTALL_DIR}/bin/${BIN_NAME}"
chmod +x "$WORK_DIR/build/index.js"

# Verify
installed_version="$("${INSTALL_DIR}/bin/${BIN_NAME}" --version 2>/dev/null || echo "unknown")"
info "Installed ${BIN_NAME}: ${installed_version}"
info "Install path: ${INSTALL_DIR}/bin/${BIN_NAME} -> ${WORK_DIR}/build/index.js"
info "Upstream SHA: $(git rev-parse --short HEAD)"
info ""
info "To verify: ${INSTALL_DIR}/bin/${BIN_NAME} --help"
info "To roll back: $0 --clean && npx -y contextplus"
