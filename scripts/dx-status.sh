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

# Resolve symlinks to get actual script directory (works on macOS and Linux)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
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

    # Stashes don't block ru sync, but they are a major cognitive-load / “lost work” source.
    local stash_count
    stash_count="$(git -C "$repo_path" stash list 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${stash_count:-0}" != "0" ]; then
        warn_only "$repo_path has $stash_count git stash entries (not durable across VMs; prefer PRs)"
    fi
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
check_file "$HOME/.cass/settings.json"

# Check local GEMINI symlink if we are inside a repo
if [ -f AGENTS.md ]; then
    if [ -L "GEMINI.md" ] && [ "$(readlink GEMINI.md)" = "AGENTS.md" ]; then
        echo -e "${GREEN}✅ GEMINI.md -> AGENTS.md linked${RESET}"
    else
        echo -e "${YELLOW}⚠️  GEMINI.md symlink missing or invalid in current dir${RESET}"
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
    warn_only "canonical-targets.sh missing CANONICAL_REQUIRED_REPOS list"
fi

# 2.6 Check for .beads/.local_version tracking
echo ""
echo "--- Beads .local_version Check ---"
check_beads_local_version() {
    local repo="$1"
    local required="${2:-0}"
    local repo_path="$HOME/$repo"
    if [ ! -d "$repo_path/.git" ]; then return 0; fi
    if git -C "$repo_path" ls-files --error-unmatch .beads/.local_version >/dev/null 2>&1; then
        if [ "$required" -eq 1 ]; then
            echo -e "${RED}❌ $repo: .beads/.local_version is tracked in git${RESET}"
            ERRORS=$((ERRORS+1))
        else
            warn_only "$repo: .beads/.local_version is tracked in git"
        fi
    else
        echo -e "${GREEN}✅ $repo: .beads/.local_version not tracked${RESET}"
    fi
}

ALL_REPOS=()
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}"); fi
if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1; then ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}"); fi
for repo in "${ALL_REPOS[@]}"; do
    check_beads_local_version "$repo" "$(is_in_list "$repo" "${CANONICAL_REQUIRED_REPOS[@]:-}" && echo 1 || echo 0)"
done

# 2.7 BEADS_DIR Check
echo ""
echo "--- External Beads Database (BEADS_DIR) ---"
check_beads_dir() {
    local expected_path="$HOME/bd/.beads"
    if [ -z "${BEADS_DIR:-}" ]; then
        echo -e "${RED}❌ BEADS_DIR not set${RESET}"
        ERRORS=$((ERRORS+1))
        return
    fi
    local beads_dir_real=$(resolve_path "$BEADS_DIR")
    local expected_real=$(resolve_path "$expected_path")
    if [ "$beads_dir_real" != "$expected_real" ]; then
        warn_only "BEADS_DIR points to non-standard location: $BEADS_DIR"
    else
        echo -e "${GREEN}✅ BEADS_DIR = $BEADS_DIR${RESET}"
    fi
    if [ ! -f "$BEADS_DIR/beads.db" ]; then
        echo -e "${RED}❌ Beads database not found at $BEADS_DIR${RESET}"
        ERRORS=$((ERRORS+1))
    else
        echo -e "${GREEN}✅ Database exists at $BEADS_DIR${RESET}"
    fi
}
check_beads_dir

# 2. Check Hooks
echo "--- Git Hooks ---"
PRIME_HOOK="$HOME/prime-radiant-ai/.git/hooks/pre-commit"
if [ -e "$PRIME_HOOK" ]; then
    if grep -q "CANONICAL COMMIT BLOCKED" "$PRIME_HOOK" 2>/dev/null || grep -q "validate_beads" "$PRIME_HOOK" 2>/dev/null; then
        echo -e "${GREEN}✅ Hook installed in prime-radiant-ai${RESET}"
    else
        warn_only "Hook invalid in prime-radiant-ai"
    fi
else
    warn_only "Hook missing in prime-radiant-ai"
fi

# 3. Check Binaries
echo "--- Required Tools ---"
if declare -p CANONICAL_REQUIRED_TOOLS >/dev/null 2>&1; then
    for t in "${CANONICAL_REQUIRED_TOOLS[@]}"; do check_binary "$t" 1; done
fi

# 3.1 Auth sanity
echo ""
echo "--- Auth Sanity (warn-only) ---"
command -v gh >/dev/null 2>&1 && { gh auth status >/dev/null 2>&1 && echo -e "${GREEN}✅ gh auth: OK${RESET}" || warn_only "gh auth: not logged in"; }
command -v railway >/dev/null 2>&1 && { railway status >/dev/null 2>&1 && echo -e "${GREEN}✅ railway auth: OK${RESET}" || warn_only "railway auth: not logged in"; }

# 4. MCP & Tooling Status
echo "--- MCP & Tooling Status ---"
if [ -f "$HOME/agent-skills/health/mcp-doctor/check.sh" ]; then
    bash "$HOME/agent-skills/health/mcp-doctor/check.sh" || true
fi

# 8. V7.8 Lifecycle / GC Metrics
echo ""
echo "--- V7.8 Lifecycle & GC Metrics ---"
WORKTREE_BASE="/tmp/agents"
if [[ -d "$WORKTREE_BASE" ]]; then
    total_wt=$(find "$WORKTREE_BASE" -mindepth 3 -maxdepth 3 -name ".git" 2>/dev/null | wc -l | tr -d ' ')
    dirty_active=0
    dirty_stale=0
    no_upstream_unmerged=0
    no_upstream_merged_clean=0
    safe_delete_wt=0
    stale_paths=()
    unmerged_paths=()
    merged_clean_paths=()
    
    current_ts=$(date +%s)
    
    while IFS= read -r gitfile; do
        wt_path=$(dirname "$gitfile")
        
        # Freshness Check (Active Session)
        is_active=false
        if [[ -f "$wt_path/.dx-session-lock" ]]; then
            lock_ts=$(cut -d: -f1 "$wt_path/.dx-session-lock" 2>/dev/null || echo "0")
            if (( current_ts - lock_ts < 14400 )); then is_active=true; fi
        fi
        if [[ "$is_active" == false ]]; then
            last_commit_ts=$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null || echo "0")
            if (( current_ts - last_commit_ts < 14400 )); then is_active=true; fi
        fi

        # Dirty Check
        status_output=$(git -C "$wt_path" status --porcelain=v1 2>/dev/null | grep -v "\.ralph" || true)
        dirty_count=$(echo "$status_output" | grep -v "^$" | wc -l | tr -d ' ')
        
        if [[ $dirty_count -gt 0 ]]; then
            if [[ "$is_active" == true ]]; then ((dirty_active++)); else ((dirty_stale++)); stale_paths+=("$wt_path"); fi
        fi
        
        # Classification of No-Upstream
        if ! git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
            branch=$(git -C "$wt_path" branch --show-current 2>/dev/null)
            if [[ -n "$branch" && "$branch" != "master" && "$branch" != "main" ]]; then
                # Determine merge status
                base="origin/master"
                git -C "$wt_path" rev-parse "$base" >/dev/null 2>&1 || base="origin/main"
                
                is_merged=false
                git -C "$wt_path" merge-base --is-ancestor HEAD "$base" 2>/dev/null && is_merged=true
                
                if [[ "$is_merged" == true && $dirty_count -eq 0 ]]; then
                    ((no_upstream_merged_clean++))
                    merged_clean_paths+=("$wt_path")
                else
                    ((no_upstream_unmerged++))
                    unmerged_paths+=("$wt_path")
                fi
            fi
        fi
        
        # Legacy SAFE DELETE metric
        branch=$(git -C "$wt_path" branch --show-current 2>/dev/null)
        if [[ -n "$branch" && "$branch" != "master" && "$branch" != "main" && $dirty_count -eq 0 ]]; then
            if git -C "$wt_path" merge-base --is-ancestor HEAD origin/master >/dev/null 2>&1 || \
               git -C "$wt_path" merge-base --is-ancestor HEAD origin/main >/dev/null 2>&1; then
                last_commit_ts=$(git -C "$wt_path" log -1 --format=%ct 2>/dev/null || echo "0")
                if (( current_ts - last_commit_ts > 86400 )); then ((safe_delete_wt++)); fi
            fi
        fi
    done < <(find "$WORKTREE_BASE" -mindepth 3 -maxdepth 3 -name ".git" 2>/dev/null)

    echo -e "   Total Worktrees: $total_wt"
    echo -e "   Dirty (Active): $dirty_active"
    
    if [[ $dirty_stale -gt 0 ]]; then
        echo -e "   ${YELLOW}⚠️  Dirty (Stale): $dirty_stale${RESET}"
        for p in "${stale_paths[@]}"; do echo "      - $p"; done
    else
        echo -e "   ${GREEN}✅ Dirty (Stale): 0${RESET}"
    fi

    if [[ $no_upstream_unmerged -gt 0 ]]; then
        echo -e "   ${RED}❌ No Upstream (Unmerged/Dirty): $no_upstream_unmerged${RESET}"
        for p in "${unmerged_paths[@]}"; do echo "      - $p"; done
        WARNINGS=$((WARNINGS+1))
    fi

    if [[ $no_upstream_merged_clean -gt 0 ]]; then
        echo -e "   ${BLUE}ℹ️  No Upstream (Merged/Clean): $no_upstream_merged_clean (GC Candidates)${RESET}"
        for p in "${merged_clean_paths[@]}"; do echo "      - $p"; done
    fi

    if [[ $safe_delete_wt -gt 0 ]]; then
        echo -e "   ${BLUE}ℹ️  SAFE DELETE Candidates: $safe_delete_wt (run 'dx-worktree-gc')${RESET}"
    fi
else
    echo "   /tmp/agents not found (skipping)"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✨ SYSTEM READY. All systems nominal.${RESET}"
    [ $WARNINGS -gt 0 ] && echo -e "${YELLOW}ℹ Found $WARNINGS warning(s).${RESET}"
    exit 0
else
    echo -e "${RED}⚠️  SYSTEM UNHEALTHY. Found $ERRORS errors.${RESET}"
    [ $WARNINGS -gt 0 ] && echo -e "${YELLOW}ℹ Also found $WARNINGS warning(s).${RESET}"
    exit 1
fi