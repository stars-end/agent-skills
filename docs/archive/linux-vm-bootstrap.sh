#!/usr/bin/env bash
# linux-vm-bootstrap.sh
# Comprehensive bootstrap for fresh Ubuntu 24.04 VM to run agent-skills ecosystem
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/stars-end/agent-skills/master/scripts/linux-vm-bootstrap.sh | bash
#   OR download and run locally after reviewing
#
# Preferences honored:
#   - Uses Homebrew (Linuxbrew) as preferred package manager
#   - Installs Tailscale for VPN/zero-config networking
#
# IMPORTANT: This script is operator-confirmed (prompts before major steps)
# NEVER prints or stores secrets (tokens, API keys, etc.)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

confirm() {
    local prompt="$1"
    read -r -p "$prompt [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

section() {
    echo ""
    echo "======================================"
    echo " $1"
    echo "======================================"
    echo ""
}

# ============================================================
# Preflight Checks
# ============================================================

preflight_check() {
    section "Preflight Check"

    # OS check
    if [[ "$(uname -s)" != "Linux" ]]; then
        error "This script is Linux-only. Detected: $(uname -s)"
        exit 1
    fi

    # Detect Ubuntu/Debian
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS distribution (/etc/os-release not found)"
        exit 1
    fi

    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        warn "This script is designed for Ubuntu/Debian. Detected: $ID"
        if ! confirm "Continue anyway?"; then
            exit 0
        fi
    fi

    success "OS: $PRETTY_NAME ($(uname -r))"

    # Running as regular user (not root)
    if [[ $EUID -eq 0 ]]; then
        error "This script should NOT be run as root."
        error "It will use sudo where needed for package installation."
        exit 1
    fi

    success "Running as user: $USER"

    # Check sudo access
    if ! sudo -v >/dev/null 2>&1; then
        error "This script requires sudo access for package installation."
        exit 1
    fi

    success "Sudo access verified"

    warn "This is an INTERACTIVE bootstrap that will prompt before major steps."
    warn "It will NEVER print or store secrets (tokens, API keys, etc.)."
    echo ""

    if ! confirm "Continue with bootstrap?"; then
        info "Bootstrap cancelled."
        exit 0
    fi
}

# ============================================================
# Phase 0: Base OS Packages
# ============================================================

install_base_packages() {
    section "Phase 0: Base OS Packages (apt)"

    info "Updating package list..."
    sudo apt-get update

    info "Installing base packages..."
    sudo apt-get install -y \
        git curl ca-certificates gnupg lsb-release unzip \
        build-essential pkg-config \
        jq ripgrep tmux \
        software-properties-common \
        apt-transport-https \
        systemd-container

    # Enable systemd linger (allows user services to persist after logout)
    info "Enabling systemd linger for user services..."
    if command -v loginctl >/dev/null 2>&1; then
        sudo loginctl enable-linger "$USER" 2>/dev/null || \
            warn "Could not enable linger (may already be enabled)"
        success "systemd linger enabled (services persist after logout)"
    else
        warn "loginctl not available, skipping linger setup"
    fi

    success "Base packages installed"
}

# ============================================================
# Phase 1: Homebrew (Linuxbrew)
# ============================================================

install_homebrew() {
    section "Phase 1: Homebrew (Linuxbrew)"

    if command -v brew >/dev/null 2>&1; then
        success "Homebrew already installed: $(brew --version | head -1)"
        eval "$("$(brew --prefix)/bin/brew" shellenv 2>/dev/null)" || true
    else
        if confirm "Install Homebrew (Linuxbrew)?"; then
            info "Running Homebrew installer..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

            # Add to shell profiles
            HOMEBREW_DIRS=(
                "/home/linuxbrew/.linuxbrew/bin/brew"
                "/opt/homebrew/bin/brew"
            )

            for brew_bin in "${HOMEBREW_DIRS[@]}"; do
                if [[ -x "$brew_bin" ]]; then
                    eval "$("$brew_bin" shellenv)"
                    break
                fi
            done

            # Add to .bashrc
            if [[ -f ~/.bashrc ]] && ! grep -q "linuxbrew" ~/.bashrc; then
                cat >> ~/.bashrc <<'EOF'

# Homebrew (Linuxbrew)
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF
            fi

            # Add to .zshrc
            if [[ -f ~/.zshrc ]] && ! grep -q "linuxbrew" ~/.zshrc; then
                cat >> ~/.zshrc <<'EOF'

# Homebrew (Linuxbrew)
if [[ -d /home/linuxbrew/.linuxbrew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF
            fi

            success "Homebrew installed"
        else
            warn "Skipping Homebrew (required for most tools)"
            return 1
        fi
    fi
}

# ============================================================
# Phase 2: mise (Toolchain Manager)
# ============================================================

install_mise() {
    section "Phase 2: mise (Toolchain Manager)"

    if command -v mise >/dev/null 2>&1; then
        success "mise already installed: $(mise --version)"
    else
        if confirm "Install mise?"; then
            info "Running mise installer..."
            curl https://mise.run | sh

            # Add to shell profiles
            if [[ -f ~/.bashrc ]] && ! grep -q "mise activate" ~/.bashrc; then
                echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
            fi
            if [[ -f ~/.zshrc ]] && ! grep -q "mise activate" ~/.zshrc; then
                echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc
            fi

            # Add to PATH for current session
            export PATH="$HOME/.local/bin:$PATH"

            success "mise installed (restart shell or run: source ~/.bashrc)"
        else
            warn "Skipping mise (required for Python/Node version management)"
        fi
    fi
}

# ============================================================
# Phase 3: Core Tools via Homebrew
# ============================================================

install_brew_tools() {
    section "Phase 3: Core Tools via Homebrew"

    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew not found. Skipping brew tools."
        return 1
    fi

    # GitHub CLI (gh)
    if command -v gh >/dev/null 2>&1; then
        success "gh already installed: $(gh --version | head -1)"
    else
        if confirm "Install GitHub CLI (gh)?"; then
            brew install gh
            success "gh installed - run 'gh auth login' to authenticate"
        fi
    fi

    # 1Password CLI (op)
    if command -v op >/dev/null 2>&1; then
        success "op already installed: $(op --version)"
    else
        if confirm "Install 1Password CLI (op)?"; then
            brew install --cask 1password-cli
            success "op installed - run 'op account add' to authenticate"
        fi
    fi

    # Tailscale (optional but preferred)
    if command -v tailscale >/dev/null 2>&1; then
        success "tailscale already installed: $(tailscale version | head -1)"
    else
        if confirm "Install Tailscale (for zero-config VPN)?"; then
            # Use tailscale's install script for Ubuntu
            curl -fsSL https://tailscale.com/install.sh | sh
            success "tailscale installed - run 'sudo tailscale up' to configure"
        fi
    fi
}

# ============================================================
# Phase 4: Railway CLI (via mise)
# ============================================================

install_railway() {
    section "Phase 4: Railway CLI (via mise)"

    if command -v railway >/dev/null 2>&1; then
        success "railway already installed: $(railway --version)"
    else
        if confirm "Install Railway CLI (via mise)?"; then
            if command -v mise >/dev/null 2>&1; then
                mise use -g global railway@latest
                success "railway installed - run 'railway login' to authenticate"
            else
                warn "mise not available, skipping railway"
            fi
        fi
    fi
}

# ============================================================
# Phase 5: Poetry (Python Dependency Manager)
# ============================================================

install_poetry() {
    section "Phase 5: Poetry (Python Dependency Manager)"

    if command -v poetry >/dev/null 2>&1; then
        success "poetry already installed: $(poetry --version)"
    else
        if confirm "Install Poetry (via pipx)?"; then
            if ! command -v pipx >/dev/null 2>&1; then
                info "Installing pipx first..."
                python3 -m pip install --user pipx
                python3 -m pipx ensurepath
            fi
            pipx install poetry
            success "poetry installed"
        fi
    fi
}

# ============================================================
# Phase 6: Beads CLI (bd)
# ============================================================

install_beads() {
    section "Phase 6: Beads CLI (bd)"

    if command -v bd >/dev/null 2>&1; then
        success "bd already installed: $(bd --version)"
    else
        if confirm "Install Beads CLI (via npm)?"; then
            if command -v npm >/dev/null 2>&1; then
                npm install -g @beadshq/beads-cli
                success "bd installed"
            else
                warn "npm not found. Install Node.js first or run: npm install -g @beadshq/beads-cli"
            fi
        fi
    fi
}

# ============================================================
# Phase 7: DCG (Destructive Command Guard)
# ============================================================

install_dcg() {
    section "Phase 7: DCG (Destructive Command Guard)"

    if command -v dcg >/dev/null 2>&1; then
        success "dcg already installed: $(dcg --version)"
    else
        if confirm "Install DCG (safety guard for destructive commands)?"; then
            curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh?$(date +%s)" | bash
            success "dcg installed"
        fi
    fi
}

# ============================================================
# Phase 8: ru (repo_updater)
# ============================================================

install_ru() {
    section "Phase 8: ru (repo_updater)"

    if command -v ru >/dev/null 2>&1; then
        success "ru already installed: $(ru --version 2>/dev/null || echo 'version unknown')"
    else
        info "Installing ru..."
        mkdir -p "$HOME/.local/bin" "$HOME/bin"
        curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/ru" -o "$HOME/.local/bin/ru"
        chmod +x "$HOME/.local/bin/ru"
        ln -sf "$HOME/.local/bin/ru" "$HOME/bin/ru" 2>/dev/null || true
        success "ru installed"
    fi
}

# ============================================================
# Phase 9: agent-skills Repository
# ============================================================

install_agent_skills() {
    section "Phase 9: agent-skills Repository"

    if [[ -d ~/agent-skills ]]; then
        success "~/agent-skills already exists"
        if confirm "Update existing agent-skills repo?"; then
            (cd ~/agent-skills && git pull origin master)
            success "agent-skills updated"
        fi
    else
        if confirm "Clone agent-skills repository?"; then
            git clone https://github.com/stars-end/agent-skills.git ~/agent-skills
            success "agent-skills cloned"

            # Create ~/.agent/skills symlink
            mkdir -p ~/.agent
            ln -sfn ~/agent-skills ~/.agent/skills
            success "~/.agent/skills -> ~/agent-skills"
        fi
    fi
}

# ============================================================
# Phase 10: DX Hydration
# ============================================================

run_dx_hydrate() {
    section "Phase 10: DX Hydration (agent-skills setup)"

    if [[ -f ~/agent-skills/scripts/dx-hydrate.sh ]]; then
        info "Running dx-hydrate..."
        bash ~/agent-skills/scripts/dx-hydrate.sh
        success "DX hydration complete"
    else
        warn "dx-hydrate.sh not found, skipping"
    fi
}

# ============================================================
# Phase 11: Canonical Repositories
# ============================================================

clone_canonical_repos() {
    section "Phase 11: Canonical Repositories"

    REPOS=(
        "prime-radiant-ai"
        "affordabot"
        "llm-common"
    )

    for repo in "${REPOS[@]}"; do
        if [[ -d ~/"$repo" ]]; then
            success "~/$repo already exists"
        else
            if confirm "Clone ~/$repo?"; then
                git clone "https://github.com/stars-end/$repo.git" ~/"$repo"
                success "~/$repo cloned"
            fi
        fi
    done
}

# ============================================================
# Phase 12: Shell Configuration
# ============================================================

configure_shell() {
    section "Phase 12: Shell Configuration"

    # Ensure PATH includes all necessary directories
    PATH_LINE='export PATH="$HOME/.local/share/mise/shims:$HOME/.local/share/mise/bin:$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"'

    for rc_file in ~/.bashrc ~/.zshrc; do
        if [[ -f "$rc_file" ]] && ! grep -q "agent-skills: shell bootstrap" "$rc_file"; then
            info "Updating $rc_file..."
            cat >> "$rc_file" <<EOF

# Agent Skills DX
alias hydrate='~/agent-skills/scripts/dx-hydrate.sh'
alias dx-check='~/agent-skills/scripts/dx-check.sh'
$PATH_LINE

# Auto-check on login
if [ -f ~/agent-skills/scripts/dx-status.sh ]; then
  ~/agent-skills/scripts/dx-status.sh >/dev/null 2>&1 || echo "⚠️  DX Environment Unhealthy. Run 'dx-check' to fix."
fi
EOF
            success "Updated $rc_file"
        fi
    done
}

# ============================================================
# Phase 13: DX_AGENT_ID
# ============================================================

configure_agent_identity() {
    section "Phase 13: Agent Identity (DX_AGENT_ID)"

    if grep -q "DX_AGENT_ID" ~/.bashrc 2>/dev/null || grep -q "DX_AGENT_ID" ~/.zshrc 2>/dev/null; then
        success "DX_AGENT_ID already configured"
    else
        HOSTNAME=$(hostname -s)
        info "Setting DX_AGENT_ID=${HOSTNAME}-claude-code"

        for rc_file in ~/.bashrc ~/.zshrc; do
            if [[ -f "$rc_file" ]] && ! grep -q "DX_AGENT_ID" "$rc_file"; then
                echo "export DX_AGENT_ID=\"\$(hostname -s)-claude-code\"" >> "$rc_file"
            fi
        done
        success "DX_AGENT_ID configured"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    echo "======================================"
    echo " Linux VM Bootstrap"
    echo " for agent-skills Ecosystem"
    echo "======================================"
    echo ""

    preflight_check
    install_base_packages
    install_homebrew
    install_mise
    install_brew_tools
    install_railway
    install_poetry
    install_beads
    install_dcg
    install_ru
    install_agent_skills
    run_dx_hydrate
    configure_shell
    configure_agent_identity

    if confirm "Clone canonical repositories (prime-radiant-ai, affordabot, llm-common)?"; then
        clone_canonical_repos
    fi

    echo ""
    section "Bootstrap Complete!"
    echo ""
    info "Next steps:"
    echo "  1. Restart your shell or run: source ~/.bashrc"
    echo "  2. Authenticate with GitHub: gh auth login"
    echo "  3. Authenticate with 1Password: op account add"
    echo "  4. Authenticate with Railway: railway login (in repo with mise)"
    echo "  5. Configure Tailscale (if installed): sudo tailscale up"
    echo "  6. Install repo-specific tools: cd ~/repo && mise install"
    echo "  7. Verify installation: dx-check"
    echo ""
    success "Done! Your VM is ready for the agent-skills ecosystem."
}

main "$@"
