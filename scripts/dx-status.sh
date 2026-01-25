#!/bin/bash
# dx-status.sh
# Agent Self-Check Tool.
# Returns 0 if healthy, 1 if action is needed.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}🩺 Checking Agent Health...${RESET}"
ERRORS=0
WARNINGS=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_TARGETS_SH="$SCRIPT_DIR/canonical-targets.sh"

# Optional: source canonical targets (VMs/IDEs/repos + trunk branch)
if [ -f "$CANONICAL_TARGETS_SH" ]; then
    # shellcheck disable=SC1090
    source "$CANONICAL_TARGETS_SH"
fi

CANONICAL_TRUNK_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"

# Cross-platform realpath
resolve_path() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || echo "$1"
}

check_file() {
    if [ -f "$1" ] || [ -L "$1" ]; then
        echo -e "${GREEN}✅ Found $1${RESET}"
    else
        echo -e "${RED}❌ Missing $1${RESET}"
        ERRORS=$((ERRORS+1))
    fi
}

check_binary() {
    local bin="$1"
    local required="${2:-1}"
    if command -v "$bin" >/dev/null 2>&1; then
         echo -e "${GREEN}✅ Binary found: $bin${RESET}"
    else
         if [ "$required" -eq 1 ]; then
             echo -e "${RED}❌ Binary missing: $bin${RESET}"
             case "$bin" in
                 bd) echo "   Fix: install Beads CLI (bd) and ensure it is on PATH" ;;
                 gh) echo "   Fix: install GitHub CLI (gh). Recommended: mise use -g gh@latest OR brew install gh" ;;
                 railway) echo "   Fix: install Railway CLI. Recommended: mise use -g railway@latest" ;;
                 op) echo "   Fix: install 1Password CLI (op). Recommended: brew install --cask 1password-cli OR brew install op" ;;
                 ru) echo "   Fix: run: $HOME/agent-skills/scripts/install-ru.sh" ;;
                 mise) echo "   Fix: run: $HOME/agent-skills/scripts/install-mise.sh" ;;
                 dcg) echo "   Fix: install dcg (see: $HOME/agent-skills/dcg-safety/SKILL.md)" ;;
                 *) echo "   Fix: install '$bin' and ensure it is on PATH" ;;
             esac
             ERRORS=$((ERRORS+1))
         else
             warn_only "Binary missing: $bin"
         fi
    fi
}

warn_only() {
    echo -e "${YELLOW}⚠️  $1${RESET}"
    WARNINGS=$((WARNINGS+1))
}

check_canonical_repo() {
    local repo="$1"
    local required="${2:-0}"
    local repo_path="$HOME/$repo"

    if [ ! -d "$repo_path/.git" ]; then
        if [ "$required" -eq 1 ]; then
            echo -e "${RED}❌ Canonical repo missing: $repo_path${RESET}"
            echo "   Fix: clone it at $repo_path (and keep on $CANONICAL_TRUNK_BRANCH for automation)"
            ERRORS=$((ERRORS+1))
            return 0
        fi
        warn_only "Canonical repo missing: $repo_path (optional on this host)"
        return 0
    fi

    local branch
    branch="$(git -C "$repo_path" branch --show-current 2>/dev/null || true)"
    if [ -z "$branch" ]; then
        branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi

    if [ "$branch" != "$CANONICAL_TRUNK_BRANCH" ]; then
        if [ "$required" -eq 1 ]; then
            echo -e "${RED}❌ $repo_path on '$branch' (expected '$CANONICAL_TRUNK_BRANCH')${RESET}"
            echo "   This blocks ru/dx automation. Keep canonical clones on trunk; use worktrees or *.wip.* directories for active work."
            ERRORS=$((ERRORS+1))
        else
            warn_only "$repo_path on '$branch' (expected '$CANONICAL_TRUNK_BRANCH' for canonical automation)"
        fi
        return 0
    fi

    if [ -n "$(git -C "$repo_path" status --porcelain=v1 2>/dev/null || true)" ]; then
        if [ "$required" -eq 1 ]; then
            echo -e "${RED}❌ $repo_path has uncommitted changes (canonical clones must stay clean)${RESET}"
            echo "   This blocks fast-forward sync. Move work to a worktree or backup dir, then reset canonical clone to trunk."
            ERRORS=$((ERRORS+1))
        else
            warn_only "$repo_path working tree dirty (canonical automation expects clean trunk)"
        fi
        return 0
    fi

    echo -e "${GREEN}✅ $repo_path clean on $CANONICAL_TRUNK_BRANCH${RESET}"
}

is_in_list() {
    local needle="$1"
    shift
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

# 1. Check Configs
echo "--- Core Configs ---"
check_file "$HOME/.ntm.yaml"
# NOTE: serena is deprecated (V4.2.1) - removed from checks
check_file "$HOME/.cass/settings.json"

# Check local GEMINI symlink if we are inside a repo
if [ -f AGENTS.md ]; then
    if [ -L "GEMINI.md" ] && [ "$(readlink GEMINI.md)" = "AGENTS.md" ]; then
        echo -e "${GREEN}✅ GEMINI.md -> AGENTS.md linked${RESET}"
    else
        echo -e "${YELLOW}⚠️  GEMINI.md symlink missing or invalid in current dir${RESET}"
        # Warn only, as we might be running from /tmp
    fi
fi

# 2.5 Canonical trunk enforcement (master)
echo "--- Canonical Git Trunk ---"
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1 && [ "${#CANONICAL_REQUIRED_REPOS[@]}" -gt 0 ]; then
    for repo in "${CANONICAL_REQUIRED_REPOS[@]}"; do
        check_canonical_repo "$repo" 1
    done
    if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1 && [ "${#CANONICAL_OPTIONAL_REPOS[@]}" -gt 0 ]; then
        for repo in "${CANONICAL_OPTIONAL_REPOS[@]}"; do
            check_canonical_repo "$repo" 0
        done
    fi
else
    warn_only "canonical-targets.sh missing CANONICAL_REQUIRED_REPOS list (expected in $CANONICAL_TARGETS_SH)"
fi

# 2.6 Check for .beads/.local_version tracking (should be gitignored)
echo ""
echo "--- Beads .local_version Check ---"
check_beads_local_version() {
    local repo="$1"
    local required="${2:-0}"
    local repo_path="$HOME/$repo"

    if [ ! -d "$repo_path/.git" ]; then
        return 0
    fi

    if git -C "$repo_path" ls-files --error-unmatch .beads/.local_version >/dev/null 2>&1; then
        if [ "$required" -eq 1 ]; then
            echo -e "${RED}❌ $repo: .beads/.local_version is tracked in git${RESET}"
            echo "   Fix: cd ~/$repo && echo '.local_version' >> .beads/.gitignore && git rm --cached .beads/.local_version && git commit -m 'fix(beads): stop tracking .local_version'"
            ERRORS=$((ERRORS+1))
        else
            warn_only "$repo: .beads/.local_version is tracked in git (should be gitignored)"
        fi
    else
        echo -e "${GREEN}✅ $repo: .beads/.local_version not tracked${RESET}"
    fi
}

# Check all canonical repos
ALL_REPOS=()
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}")
fi
if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}")
fi

for repo in "${ALL_REPOS[@]}"; do
    if is_in_list "$repo" "${CANONICAL_REQUIRED_REPOS[@]:-}"; then
        check_beads_local_version "$repo" 1
    else
        check_beads_local_version "$repo" 0
    fi
done

# 2. Check Hooks (V3 Logic)
echo "--- Git Hooks ---"
PRIME_HOOK="$HOME/prime-radiant-ai/.git/hooks/pre-commit"
PRIME_REQUIRED=0
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then
    if is_in_list "prime-radiant-ai" "${CANONICAL_REQUIRED_REPOS[@]}"; then
        PRIME_REQUIRED=1
    fi
fi

# Check if hook exists (symlink or file)
if [ -e "$PRIME_HOOK" ]; then
    IS_VALID=0
    
    # Method A: V3 Symlink
    if [ -L "$PRIME_HOOK" ]; then
        TARGET=$(resolve_path "$PRIME_HOOK")
        if [[ "$TARGET" == *"permission-sentinel"* ]]; then
            IS_VALID=1
        fi
    fi
    
    # Method B: Legacy/Content Check
    if [ $IS_VALID -eq 0 ] && [ -f "$PRIME_HOOK" ]; then
        if grep -q "validate_beads" "$PRIME_HOOK" 2>/dev/null; then
            IS_VALID=1
        elif grep -q "permission-sentinel" "$PRIME_HOOK" 2>/dev/null; then
            IS_VALID=1
        fi
    fi

    if [ $IS_VALID -eq 1 ]; then
        echo -e "${GREEN}✅ Hook installed in prime-radiant-ai${RESET}"
    else
        if [ $PRIME_REQUIRED -eq 1 ]; then
            echo -e "${RED}❌ Hook invalid in prime-radiant-ai${RESET}"
            echo "   Target: $(resolve_path $PRIME_HOOK)"
            echo "   Fix: Run ~/agent-skills/git-safety-guard/install.sh --global"
            ERRORS=$((ERRORS+1))
        else
            warn_only "Hook invalid in prime-radiant-ai (optional on this host)"
        fi
    fi
else
    if [ $PRIME_REQUIRED -eq 1 ]; then
        echo -e "${RED}❌ Hook missing in prime-radiant-ai${RESET}"
        echo "   Fix: Run ~/agent-skills/git-safety-guard/install.sh --global"
        ERRORS=$((ERRORS+1))
    else
        warn_only "Hook missing in prime-radiant-ai (optional on this host)"
    fi
fi

# 3. Check Binaries
echo "--- Required Tools ---"
if declare -p CANONICAL_REQUIRED_TOOLS >/dev/null 2>&1; then
    for t in "${CANONICAL_REQUIRED_TOOLS[@]}"; do
        check_binary "$t" 1
    done
fi
if declare -p CANONICAL_OPTIONAL_TOOLS >/dev/null 2>&1; then
    for t in "${CANONICAL_OPTIONAL_TOOLS[@]}"; do
        check_binary "$t" 0
    done
fi

# 3.1 Auth sanity (warn-only; binaries are the hard requirement)
echo ""
echo "--- Auth Sanity (warn-only) ---"

if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        echo -e "${GREEN}✅ gh auth: OK${RESET}"
    else
        warn_only "gh auth: not logged in (run: gh auth login)"
    fi
fi

if command -v railway >/dev/null 2>&1; then
    if railway status >/dev/null 2>&1; then
        echo -e "${GREEN}✅ railway auth: OK${RESET}"
    else
        warn_only "railway auth: not logged in (run: railway login) or set RAILWAY_TOKEN"
    fi
fi

if command -v op >/dev/null 2>&1; then
    if op whoami >/dev/null 2>&1; then
        echo -e "${GREEN}✅ op auth: OK${RESET}"
    else
        warn_only "op auth: not available (expected if using service tokens only); verify op account/sign-in if needed"
    fi
fi

# 4. Invoke MCP Doctor
echo "--- MCP & Tooling Status ---"
if [ -f "$HOME/agent-skills/mcp-doctor/check.sh" ]; then
    # mcp-doctor is warn-only by default; strict mode should be enabled explicitly.
    bash "$HOME/agent-skills/mcp-doctor/check.sh" || true
else
    echo -e "${RED}❌ MCP Doctor script missing${RESET}"
    ERRORS=$((ERRORS+1))
fi

# 5. SSH Key Doctor (warn-only by default)
echo ""
echo "--- SSH Key Doctor ---"
SSH_DOCTOR="$HOME/agent-skills/ssh-key-doctor/check.sh"
if [ -x "$SSH_DOCTOR" ]; then
    # Local-only is fast and safe; remote checks are opt-in.
    if ! "$SSH_DOCTOR" --local-only; then
        WARNINGS=$((WARNINGS+1))
    fi

    if [ "${DX_SSH_DOCTOR_REMOTE:-0}" = "1" ]; then
        if ! "$SSH_DOCTOR" --remote-only; then
            WARNINGS=$((WARNINGS+1))
        fi
    else
        echo "ℹ Remote SSH checks skipped (set DX_SSH_DOCTOR_REMOTE=1 to enable)."
    fi
else
    echo -e "${YELLOW}⚠️  ssh-key-doctor not installed${RESET}"
    echo "   Run: ~/agent-skills/ssh-key-doctor/check.sh"
    WARNINGS=$((WARNINGS+1))
fi

# 6. Railway Requirements Check (hard-fail only when required by ENV_SOURCES_MODE)
echo ""
echo "--- Railway Requirements ---"
if [ -f "$SCRIPT_DIR/railway-requirements-check.sh" ]; then
    # Default to local-dev unless caller explicitly sets ENV_SOURCES_MODE
    # (important: dx-status is often run in non-interactive tooling).
    RAILWAY_MODE="${ENV_SOURCES_MODE:-}"
    if [ -z "$RAILWAY_MODE" ] && [ -n "${CI:-}" ]; then
        RAILWAY_MODE="ci"
    fi
    RAILWAY_MODE="${RAILWAY_MODE:-local-dev}"

    if ! bash "$SCRIPT_DIR/railway-requirements-check.sh" --mode "$RAILWAY_MODE"; then
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "${YELLOW}⚠️  Railway requirements check script missing${RESET}"
    WARNINGS=$((WARNINGS+1))
fi

# 7. Auto-checkpoint Status (Phase 1: warn-only during rollout)
echo ""
echo "--- Auto-checkpoint Status ---"
CHECKPOINT_SCRIPT="$SCRIPT_DIR/auto-checkpoint.sh"
CHECKPOINT_LOG_DIR="${AUTO_CHECKPOINT_LOG_DIR:-$HOME/.auto-checkpoint}"

if [ -f "$CHECKPOINT_SCRIPT" ]; then
    echo -e "${GREEN}✅ auto-checkpoint installed${RESET}"

    # Check scheduler status
    case "$(uname -s)" in
        Linux*)
            if systemctl --user is-active auto-checkpoint.timer >/dev/null 2>&1; then
                echo -e "${GREEN}✅ auto-checkpoint timer active (systemd)${RESET}"
            else
                echo -e "${YELLOW}⚠️  auto-checkpoint timer not active${RESET}"
                echo "   Fix: auto-checkpoint-install --status"
                WARNINGS=$((WARNINGS+1))
            fi
            ;;
        Darwin*)
            if launchctl list 2>/dev/null | grep -q "auto-checkpoint"; then
                echo -e "${GREEN}✅ auto-checkpoint timer active (launchd)${RESET}"
            else
                echo -e "${YELLOW}⚠️  auto-checkpoint timer not active${RESET}"
                echo "   Fix: auto-checkpoint-install --status"
                WARNINGS=$((WARNINGS+1))
            fi
            ;;
        *)
            echo -e "${YELLOW}⚠️  Unknown OS, cannot verify scheduler${RESET}"
            WARNINGS=$((WARNINGS+1))
            ;;
    esac

    # Check last run
    if [ -f "$CHECKPOINT_LOG_DIR/last-run" ]; then
        last_run_ts=$(cat "$CHECKPOINT_LOG_DIR/last-run")
        current_ts=$(date +%s)
        minutes_since=$(( (current_ts - last_run_ts) / 60 ))

        if [ $minutes_since -lt 30 ]; then
            echo -e "${GREEN}✅ Last run: ${minutes_since}m ago${RESET}"
        elif [ $minutes_since -lt 120 ]; then
            echo -e "${YELLOW}⚠️  Last run: ${minutes_since}m ago${RESET}"
            WARNINGS=$((WARNINGS+1))
        else
            echo -e "${RED}❌ Last run: ${minutes_since}m ago (may be stale)${RESET}"
            echo "   Fix: auto-checkpoint-install --status"
            ERRORS=$((ERRORS+1))
        fi
    else
        echo -e "${YELLOW}⚠️  Auto-checkpoint never ran${RESET}"
        echo "   Fix: auto-checkpoint-install --run (test run)"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠️  auto-checkpoint not installed${RESET}"
    echo "   Run: auto-checkpoint-install (or dx-hydrate)"
    WARNINGS=$((WARNINGS+1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✨ SYSTEM READY. All systems nominal.${RESET}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}ℹ Found $WARNINGS warning(s).${RESET}"
    fi
    exit 0
else
    echo -e "${RED}⚠️  SYSTEM UNHEALTHY. Found $ERRORS errors.${RESET}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}ℹ Also found $WARNINGS warning(s).${RESET}"
    fi
    echo -e "${YELLOW}💡 TROUBLESHOOTING: Read ~/agent-skills/memory/playbooks/99_TROUBLESHOOTING.md for fixes.${RESET}"
    exit 1
fi
