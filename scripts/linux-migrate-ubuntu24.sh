#!/usr/bin/env bash
# linux-migrate-ubuntu24.sh
# Comprehensive backup/restore for migrating Debian 12 → Ubuntu 24.04
# Run this on CURRENT machine to create migration bundle
# Then run with --restore on NEW Ubuntu 24.04 machine
#
# Usage:
#   ./linux-migrate-ubuntu24.sh --export     # On current Debian 12
#   ./linux-migrate-ubuntu24.sh --restore    # On new Ubuntu 24.04

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }
section() {
    echo ""
    echo "======================================"
    echo " $1"
    echo "======================================"
    echo ""
}

# ============================================================
# CONFIGURATION
# ============================================================

EXPORT_DIR="$HOME/linux-migration-bundle"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BUNDLE_FILE="linux-migration-${TIMESTAMP}.tar.gz"
HOSTNAME="$(hostname)"

# ============================================================
# EXPORT MODE (run on OLD Debian)
# ============================================================

do_export() {
    section "Creating Migration Bundle for $HOSTNAME"

    mkdir -p "$EXPORT_DIR"

    # ----------------------------------------------------------
    # 1. System Information
    # ----------------------------------------------------------
    info "Capturing system information..."
    {
        echo "=== Hostname ==="
        hostname
        echo "=== IP Addresses ==="
        hostname -I
        echo "=== OS Release ==="
        cat /etc/os-release
        echo "=== Kernel ==="
        uname -a
        echo "=== glibc version ==="
        ldd --version | head -1
    } > "$EXPORT_DIR/system-info.txt"

    # ----------------------------------------------------------
    # 2. Shell Configurations
    # ----------------------------------------------------------
    info "Exporting shell configurations..."
    cp ~/.zshrc "$EXPORT_DIR/" 2>/dev/null || true
    cp ~/.zshenv "$EXPORT_DIR/" 2>/dev/null || true
    cp ~/.bashrc "$EXPORT_DIR/" 2>/dev/null || true
    cp ~/.bash_profile "$EXPORT_DIR/" 2>/dev/null || true
    cp ~/.profile "$EXPORT_DIR/" 2>/dev/null || true
    cp ~/.npmrc "$EXPORT_DIR/" 2>/dev/null || true

    success "Shell configs exported"

    # ----------------------------------------------------------
    # 3. SSH Keys
    # ----------------------------------------------------------
    info "Exporting SSH keys..."
    mkdir -p "$EXPORT_DIR/ssh"
    cp ~/.ssh/id_* "$EXPORT_DIR/ssh/" 2>/dev/null || true
    cp ~/.ssh/*.pub "$EXPORT_DIR/ssh/" 2>/dev/null || true
    cp ~/.ssh/config "$EXPORT_DIR/ssh/" 2>/dev/null || true
    cp ~/.ssh/authorized_keys "$EXPORT_DIR/ssh/" 2>/dev/null || true
    cp ~/.ssh/known_hosts "$EXPORT_DIR/ssh/" 2>/dev/null || true
    chmod 600 "$EXPORT_DIR/ssh/"* 2>/dev/null || true

    success "SSH keys exported"

    # ----------------------------------------------------------
    # 4. Git Configuration
    # ----------------------------------------------------------
    info "Exporting git configuration..."
    cp ~/.gitconfig "$EXPORT_DIR/" 2>/dev/null || true

    success "Git config exported"

    # ----------------------------------------------------------
    # 5. GitHub CLI (gh) - already authenticated via GitHub, just need config
    # ----------------------------------------------------------
    info "Exporting GitHub CLI config..."
    mkdir -p "$EXPORT_DIR/config/gh"
    cp -r ~/.config/gh "$EXPORT_DIR/config/" 2>/dev/null || true
    # Note: gh auth uses GitHub OAuth - will re-auth on new machine

    success "GitHub CLI config exported"

    # ----------------------------------------------------------
    # 6. 1Password CLI (op) - session NOT portable, need to re-auth
    # ----------------------------------------------------------
    info "Exporting 1Password CLI config..."
    mkdir -p "$EXPORT_DIR/config/op"
    cp -r ~/.config/op "$EXPORT_DIR/config/" 2>/dev/null || true

    success "1Password config exported (will need re-auth)"

    # ----------------------------------------------------------
    # 7. mise (toolchain manager) configuration
    # ----------------------------------------------------------
    info "Exporting mise configuration..."
    mkdir -p "$EXPORT_DIR/config/mise"
    cp ~/.config/mise/config.toml "$EXPORT_DIR/config/mise/" 2>/dev/null || true
    mise list > "$EXPORT_DIR/mise-tools.txt" 2>/dev/null || true

    success "mise config exported"

    # ----------------------------------------------------------
    # 8. Homebrew package list
    # ----------------------------------------------------------
    info "Exporting Homebrew packages..."
    brew list > "$EXPORT_DIR/brew-packages.txt" 2>/dev/null || true
    brew list --cask > "$EXPORT_DIR/brew-casks.txt" 2>/dev/null || true

    success "Homebrew package list exported"

    # ----------------------------------------------------------
    # 9. Claude Code configuration
    # ----------------------------------------------------------
    info "Exporting Claude Code config..."
    mkdir -p "$EXPORT_DIR/config/claude"
    cp ~/.claude.json "$EXPORT_DIR/config/claude/" 2>/dev/null || true
    cp -r ~/.claude/hooks "$EXPORT_DIR/config/claude/" 2>/dev/null || true

    success "Claude Code config exported"

    # ----------------------------------------------------------
    # 10. systemd user services
    # ----------------------------------------------------------
    info "Exporting systemd user services..."
    mkdir -p "$EXPORT_DIR/systemd/user"
    cp ~/.config/systemd/user/*.service "$EXPORT_DIR/systemd/user/" 2>/dev/null || true
    cp ~/.config/systemd/user/*.timer "$EXPORT_DIR/systemd/user/" 2>/dev/null || true

    # CRITICAL: Export op tokens (contains service account credentials)
    info "Exporting systemd service tokens (contains secrets)..."
    mkdir -p "$EXPORT_DIR/systemd/tokens"
    cp ~/.config/systemd/user/op*token* "$EXPORT_DIR/systemd/tokens/" 2>/dev/null || true
    chmod 600 "$EXPORT_DIR/systemd/tokens/"* 2>/dev/null || true

    success "Systemd services exported"

    # ----------------------------------------------------------
    # 11. opencode and slack-coordinator env templates
    # ----------------------------------------------------------
    info "Exporting service environment templates..."
    mkdir -p "$EXPORT_DIR/config/opencode"
    mkdir -p "$EXPORT_DIR/config/slack-coordinator"
    cp ~/.config/opencode/.env "$EXPORT_DIR/config/opencode/" 2>/dev/null || true
    cp ~/.config/slack-coordinator/.env "$EXPORT_DIR/config/slack-coordinator/" 2>/dev/null || true

    success "Service env templates exported"

    # ----------------------------------------------------------
    # 12. Cron jobs
    # ----------------------------------------------------------
    info "Exporting cron jobs..."
    crontab -l > "$EXPORT_DIR/crontab.txt" 2>/dev/null || true

    success "Cron jobs exported"

    # ----------------------------------------------------------
    # 13. GitHub Actions Runners (CRITICAL - need to re-register)
    # ----------------------------------------------------------
    info "Exporting GitHub Actions Runner information..."
    mkdir -p "$EXPORT_DIR/actions-runners"

    # Runner service files (system-level)
    if [[ -d /etc/systemd/system ]]; then
        sudo cp /etc/systemd/system/actions.runner.*.service "$EXPORT_DIR/actions-runners/" 2>/dev/null || true
    fi

    # Runner registration info (for reference - tokens expire)
    for runner_dir in ~/actions-runner-*; do
        if [[ -d "$runner_dir" ]]; then
            runner_name=$(basename "$runner_dir")
            info "  Found runner: $runner_name"

            # Copy .runner file for reference (contains pool info)
            cp "$runner_dir/.runner" "$EXPORT_DIR/actions-runners/${runner_name}.runner.json" 2>/dev/null || true

            # Copy service file (for reference)
            cp "$runner_dir/.service" "$EXPORT_DIR/actions-runners/${runner_name}.service" 2>/dev/null || true

            echo "$runner_name" >> "$EXPORT_DIR/actions-runners/list.txt"
        fi
    done

    success "Actions runner info exported"

    # ----------------------------------------------------------
    # 14. Tailscale status
    # ----------------------------------------------------------
    info "Exporting Tailscale status..."
    if command -v tailscale >/dev/null 2>&1; then
        tailscale status > "$EXPORT_DIR/tailscale-status.txt" 2>/dev/null || true
        tailscale status --json > "$EXPORT_DIR/tailscale-status.json" 2>/dev/null || true

        # Note: Machine key is in /var/lib/tailscale/ - needs sudo to migrate
        # Tailscale will need to be re-authenticated on new machine
    fi

    success "Tailscale status exported"

    # ----------------------------------------------------------
    # 15. Repo list
    # ----------------------------------------------------------
    info "Creating repo list..."
    cat > "$EXPORT_DIR/repos.txt" <<EOF
agent-skills
prime-radiant-ai
affordabot
llm-common
EOF

    success "Repo list created"

    # ----------------------------------------------------------
    # 16. Docker status
    # ----------------------------------------------------------
    info "Exporting Docker status..."
    if command -v docker >/dev/null 2>&1; then
        docker ps -a > "$EXPORT_DIR/docker-containers.txt" 2>/dev/null || true
        docker images > "$EXPORT_DIR/docker-images.txt" 2>/dev/null || true
        docker volume ls > "$EXPORT_DIR/docker-volumes.txt" 2>/dev/null || true
    fi

    success "Docker status exported"

    # ----------------------------------------------------------
    # 17. Create RESTORE script
    # ----------------------------------------------------------
    info "Creating restore script..."
    cat > "$EXPORT_DIR/restore.sh" <<'RESTORE_SCRIPT'
#!/usr/bin/env bash
# restore.sh - Run on NEW Ubuntu 24.04 machine

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
info() { echo -e "${BLUE}ℹ${NC} $*"; }

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW_HOSTNAME="$(hostname)"

echo "======================================"
echo " Linux Migration Restore"
echo "======================================"
echo ""
info "Bundle: $BUNDLE_DIR"
info "Old hostname: $(cat $BUNDLE_DIR/system-info.txt | grep Hostname | cut -d' ' -f2-)"
info "New hostname: $NEW_HOSTNAME"
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# ----------------------------------------------------------
# 1. Restore shell configs
# ----------------------------------------------------------
info "Restoring shell configurations..."
cp "$BUNDLE_DIR/.zshrc" ~/ 2>/dev/null || true
cp "$BUNDLE_DIR/.zshenv" ~/ 2>/dev/null || true
cp "$BUNDLE_DIR/.bashrc" ~/ 2>/dev/null || true
cp "$BUNDLE_DIR/.bash_profile" ~/ 2>/dev/null || true
cp "$BUNDLE_DIR/.profile" ~/ 2>/dev/null || true
cp "$BUNDLE_DIR/.npmrc" ~/ 2>/dev/null || true
success "Shell configs restored"

# ----------------------------------------------------------
# 2. Restore SSH keys
# ----------------------------------------------------------
info "Restoring SSH keys..."
mkdir -p ~/.ssh
cp "$BUNDLE_DIR/ssh/"* ~/.ssh/ 2>/dev/null || true
chmod 600 ~/.ssh/id_* 2>/dev/null || true
chmod 644 ~/.ssh/*.pub 2>/dev/null || true
success "SSH keys restored"

# ----------------------------------------------------------
# 3. Restore git config
# ----------------------------------------------------------
info "Restoring git configuration..."
cp "$BUNDLE_DIR/.gitconfig" ~/ 2>/dev/null || true
success "Git config restored"

# ----------------------------------------------------------
# 4. Restore GitHub CLI config
# ----------------------------------------------------------
info "Restoring GitHub CLI config..."
mkdir -p ~/.config
cp -r "$BUNDLE_DIR/config/gh" ~/.config/ 2>/dev/null || true
warn "GitHub CLI will need re-auth: gh auth login"
success "GitHub CLI config restored"

# ----------------------------------------------------------
# 5. Restore 1Password config
# ----------------------------------------------------------
info "Restoring 1Password config..."
cp -r "$BUNDLE_DIR/config/op" ~/.config/ 2>/dev/null || true
warn "1Password CLI will need re-auth: op account add"
success "1Password config restored"

# ----------------------------------------------------------
# 6. Restore mise config
# ----------------------------------------------------------
info "Restoring mise configuration..."
mkdir -p ~/.config/mise
cp "$BUNDLE_DIR/config/mise/config.toml" ~/.config/mise/ 2>/dev/null || true
success "mise config restored"

# ----------------------------------------------------------
# 7. Restore Claude Code config
# ----------------------------------------------------------
info "Restoring Claude Code config..."
mkdir -p ~/.claude
cp "$BUNDLE_DIR/config/claude/claude.json" ~/.claude/.claude.json 2>/dev/null || true
cp -r "$BUNDLE_DIR/config/claude/hooks" ~/.claude/ 2>/dev/null || true
success "Claude Code config restored"

# ----------------------------------------------------------
# 8. Restore systemd services
# ----------------------------------------------------------
info "Restoring systemd user services..."
mkdir -p ~/.config/systemd/user
cp "$BUNDLE_DIR/systemd/user/"*.service ~/.config/systemd/user/ 2>/dev/null || true
cp "$BUNDLE_DIR/systemd/user/"*.timer ~/.config/systemd/user/ 2>/dev/null || true

# Restore op tokens
mkdir -p ~/.config/systemd/user
cp "$BUNDLE_DIR/systemd/tokens/"* ~/.config/systemd/user/ 2>/dev/null || true
chmod 600 ~/.config/systemd/user/op*token* 2>/dev/null || true

systemctl --user daemon-reload 2>/dev/null || true
success "Systemd services restored"

# ----------------------------------------------------------
# 9. Restore service env templates
# ----------------------------------------------------------
info "Restoring service environment templates..."
mkdir -p ~/.config/opencode
mkdir -p ~/.config/slack-coordinator
cp "$BUNDLE_DIR/config/opencode/.env" ~/.config/opencode/ 2>/dev/null || true
cp "$BUNDLE_DIR/config/slack-coordinator/.env" ~/.config/slack-coordinator/ 2>/dev/null || true
success "Service env templates restored"

# ----------------------------------------------------------
# 10. Restore cron jobs
# ----------------------------------------------------------
info "Restoring cron jobs..."
crontab "$BUNDLE_DIR/crontab.txt" 2>/dev/null || true
success "Cron jobs restored"

# ----------------------------------------------------------
# 11. Reinstall brew packages
# ----------------------------------------------------------
info "Reinstalling Homebrew packages..."
if [[ -f "$BUNDLE_DIR/brew-packages.txt" ]]; then
    while read -r pkg; do
        info "  Installing $pkg..."
        brew install "$pkg" 2>/dev/null || warn "Failed to install $pkg"
    done < "$BUNDLE_DIR/brew-packages.txt"
fi
success "Homebrew packages reinstalled"

# ----------------------------------------------------------
# 12. Summary of manual steps
# ----------------------------------------------------------
echo ""
info "=========================================="
info "Manual Steps Required"
info "=========================================="
echo ""
warn "1. Clone repositories:"
echo "   cd ~"
for repo in $(cat "$BUNDLE_DIR/repos.txt" 2>/dev/null); do
    echo "   git clone https://github.com/stars-end/$repo.git"
done
echo ""
warn "2. Install mise tools in each repo:"
echo "   cd ~/agent-skills && mise install"
echo "   cd ~/prime-radiant-ai && mise install"
echo "   cd ~/affordabot && mise install"
echo "   cd ~/llm-common && mise install"
echo ""
warn "3. Re-authenticate tools:"
echo "   gh auth login"
echo "   op account add"
echo "   railway login"
echo ""
warn "4. Re-authenticate Tailscale:"
echo "   sudo tailscale up"
echo ""
warn "5. Re-register GitHub Actions Runners:"
echo "   See $BUNDLE_DIR/actions-runners/ for reference"
echo "   - Go to repo Settings → Actions → Runners"
echo "   - Remove old runner for $HOSTNAME"
echo "   - Run: ./actions-runner-config.sh in each runner dir"
echo ""
warn "6. Update hostname references in systemd services:"
echo "   Old hostname: $(cat $BUNDLE_DIR/system-info.txt | grep Hostname | cut -d' ' -f2-)"
echo "   New hostname: $NEW_HOSTNAME"
echo "   Edit: ~/.config/systemd/user/*.service"
echo ""
warn "7. Verify systemd services:"
echo "   systemctl --user status opencode"
echo "   systemctl --user status slack-coordinator"
echo "   systemctl --user start opencode"
echo "   systemctl --user start slack-coordinator"
echo ""
warn "8. Verify crontab loaded:"
echo "   crontab -l"
echo ""
success "Restore complete! Follow manual steps above."
RESTORE_SCRIPT

    chmod +x "$EXPORT_DIR/restore.sh"

    # ----------------------------------------------------------
    # 18. Create bundle archive
    # ----------------------------------------------------------
    info "Creating bundle archive..."
    cd "$HOME"
    tar -czf "$BUNDLE_FILE" -C "$EXPORT_DIR" .

    success "Bundle created: $BUNDLE_FILE"
    info "Size: $(du -h "$BUNDLE_FILE" | cut -f1)"

    echo ""
    info "=========================================="
    info "Export Complete!"
    info "=========================================="
    echo ""
    info "Bundle: $HOME/$BUNDLE_FILE"
    echo "Directory: $EXPORT_DIR"
    echo ""
    warn "IMPORTANT: Keep this bundle secure - contains:"
    warn "  - SSH private keys"
    warn "  - 1Password service account tokens"
    warn "  - GitHub OAuth tokens (in gh config)"
    echo ""
    info "Next steps:"
    echo "  1. Copy bundle to new Ubuntu 24.04 machine"
    echo "  2. Extract: tar -xzf $BUNDLE_FILE"
    echo "  3. Run: cd linux-migration-bundle && ./restore.sh"
    echo ""
}

# ============================================================
# RESTORE MODE (run on NEW Ubuntu 24.04)
# ============================================================

do_restore() {
    local bundle_path="$1"

    if [[ ! -f "$bundle_path" ]]; then
        error "Bundle not found: $bundle_path"
        exit 1
    fi

    section "Extracting Migration Bundle"

    mkdir -p "$EXPORT_DIR"
    tar -xzf "$bundle_path" -C "$EXPORT_DIR"

    info "Bundle extracted to: $EXPORT_DIR"
    echo ""

    section "Running Restore Script"

    bash "$EXPORT_DIR/restore.sh"
}

# ============================================================
# Main
# ============================================================

main() {
    if [[ "${1:-}" == "--export" ]]; then
        do_export
    elif [[ "${1:-}" == "--restore" ]]; then
        if [[ -z "${2:-}" ]]; then
            error "Usage: $0 --restore <bundle-path.tar.gz>"
            exit 1
        fi
        do_restore "$2"
    else
        cat <<USAGE
Linux Migration: Debian 12 → Ubuntu 24.04

Usage:
  $0 --export                    # Run on OLD Debian 12
  $0 --restore <bundle.tar.gz>   # Run on NEW Ubuntu 24.04

What gets backed up:
  ✓ Shell configs (.zshrc, .zshenv, .bashrc, etc)
  ✓ SSH keys (private + public)
  ✓ Git configuration
  ✓ GitHub CLI config (needs re-auth)
  ✓ 1Password config (needs re-auth)
  ✓ mise toolchain config
  ✓ Homebrew package list
  ✓ Claude Code config + hooks
  ✓ systemd user services + tokens
  ✓ opencode/slack-coordinator env templates
  ✓ Cron jobs
  ✓ GitHub Actions Runner reference (needs re-register)
  ✓ Tailscale status (needs re-auth)
  ✓ Docker status
  ✓ Repo list

Manual steps after restore:
  - Clone repositories
  - Run mise install in each repo
  - gh auth login
  - op account add
  - railway login
  - sudo tailscale up
  - Re-register GitHub Actions Runners
  - Update hostname references in services
  - Verify systemd services
USAGE
    fi
}

main "$@"
