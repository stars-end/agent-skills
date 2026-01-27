#!/usr/bin/env bash
# dx-triage.sh
# Information-first repo state diagnosis + safe recovery.
#
# Unlike dx-check (which just detects issues), dx-triage:
# 1. Surveys ALL canonical repos
# 2. Classifies each: OK, STALE, DIRTY, FEATURE-MERGED, FEATURE-ACTIVE
# 3. Shows recommendations
# 4. --fix mode only does SAFE operations (never loses work)
#
# Usage:
#   dx-triage              # Show current state
#   dx-triage --fix        # Apply safe fixes only
#   dx-triage --ack        # Acknowledge flag and clear (I know what I'm doing)
#   dx-triage --force      # Reset all to trunk (DANGEROUS - stashes WIP)

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Resolve symlinks to get actual script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

CANONICAL_TRUNK_BRANCH="${CANONICAL_TRUNK_BRANCH:-master}"

MODE="${1:-status}"
case "$MODE" in
    --fix) MODE="fix" ;;
    --ack) MODE="ack" ;;
    --force) MODE="force" ;;
    --help|-h) MODE="help" ;;
    *) MODE="status" ;;
esac

if [[ "$MODE" == "help" ]]; then
    cat <<EOF
dx-triage - Repo state diagnosis and safe recovery

Usage:
  dx-triage              Show current state of all repos
  dx-triage --fix        Apply safe fixes (pull stale, reset merged branches)
  dx-triage --ack        Acknowledge triage flags and clear (I know what I'm doing)
  dx-triage --force      Reset ALL repos to trunk (DANGEROUS - stashes WIP first)
  dx-triage --help       Show this help

States:
  OK             On trunk, clean, up-to-date
  STALE          On trunk, clean, behind origin (safe to pull)
  DIRTY          Has uncommitted changes (needs manual decision)
  FEATURE-MERGED On feature branch that's been merged (safe to reset)
  FEATURE-ACTIVE On feature branch with unmerged work (needs manual decision)

Safe fixes (--fix):
  - Fetches all repos
  - Pulls stale repos
  - Resets FEATURE-MERGED branches to trunk
  - NEVER touches DIRTY or FEATURE-ACTIVE repos
  - Clears triage flags after fixing

Ack mode (--ack):
  - Clears .git/DX_TRIAGE_REQUIRED flags
  - Records acknowledgment timestamp
  - Use when you've reviewed the state and want to proceed anyway

Force mode (--force):
  - Stashes any uncommitted work
  - Resets ALL repos to trunk
  - Use only when you're sure no WIP matters
EOF
    exit 0
fi

# Collect all repos to check
ALL_REPOS=()
if declare -p CANONICAL_REQUIRED_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_REQUIRED_REPOS[@]}")
fi
if declare -p CANONICAL_OPTIONAL_REPOS >/dev/null 2>&1; then
    ALL_REPOS+=("${CANONICAL_OPTIONAL_REPOS[@]}")
fi

if [[ ${#ALL_REPOS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No canonical repos defined${RESET}"
    exit 1
fi

# State tracking
declare -A REPO_STATE
declare -A REPO_BRANCH
declare -A REPO_BEHIND
declare -A REPO_AHEAD
declare -A REPO_DIRTY
declare -A REPO_STASH_COUNT
declare -A REPO_MERGED
declare -A REPO_EXISTS

echo -e "${BLUE}=== dx-triage ($(hostname -s 2>/dev/null || hostname)) ===${RESET}"
echo ""

# Phase 1: Survey all repos
echo -e "${CYAN}Surveying repos...${RESET}"
for repo in "${ALL_REPOS[@]}"; do
    repo_path="$HOME/$repo"

    if [[ ! -d "$repo_path/.git" ]]; then
        REPO_EXISTS[$repo]=0
        REPO_STATE[$repo]="MISSING"
        continue
    fi
    REPO_EXISTS[$repo]=1

    cd "$repo_path"

    # Fetch silently to get accurate behind/ahead counts
    git fetch origin --quiet 2>/dev/null || true

    # Get current branch
    branch="$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    REPO_BRANCH[$repo]="$branch"

    # Check dirty state
    dirty_count=$(git status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')
    REPO_DIRTY[$repo]="$dirty_count"

    # Count stashes
    stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
    REPO_STASH_COUNT[$repo]="$stash_count"

    # Check behind/ahead of origin
    behind=0
    ahead=0
    if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
        behind=$(git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)
        ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)
    elif [[ "$branch" != "$CANONICAL_TRUNK_BRANCH" ]]; then
        # Feature branch - check against trunk
        if git rev-parse --verify "origin/$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
            behind=$(git rev-list --count "HEAD..origin/$CANONICAL_TRUNK_BRANCH" 2>/dev/null || echo 0)
        fi
    fi
    REPO_BEHIND[$repo]="$behind"
    REPO_AHEAD[$repo]="$ahead"

    # Check if feature branch has been merged to trunk
    merged=0
    if [[ "$branch" != "$CANONICAL_TRUNK_BRANCH" && "$branch" != "main" ]]; then
        # Check if branch is fully merged into origin/master
        if git merge-base --is-ancestor HEAD "origin/$CANONICAL_TRUNK_BRANCH" 2>/dev/null; then
            merged=1
        fi
    fi
    REPO_MERGED[$repo]="$merged"

    # Determine state
    if [[ "$dirty_count" -gt 0 ]]; then
        REPO_STATE[$repo]="DIRTY"
    elif [[ "$branch" == "$CANONICAL_TRUNK_BRANCH" || "$branch" == "main" ]]; then
        if [[ "$behind" -gt 0 ]]; then
            REPO_STATE[$repo]="STALE"
        else
            REPO_STATE[$repo]="OK"
        fi
    else
        # On feature branch
        if [[ "$merged" -eq 1 ]]; then
            REPO_STATE[$repo]="FEATURE-MERGED"
        else
            REPO_STATE[$repo]="FEATURE-ACTIVE"
        fi
    fi
done

# Phase 2: Display results
echo ""
printf "%-18s %-16s %-20s %-8s %s\n" "REPO" "STATE" "BRANCH" "STASHES" "DETAILS"
printf "%-18s %-16s %-20s %-8s %s\n" "----" "-----" "------" "-------" "-------"

for repo in "${ALL_REPOS[@]}"; do
    state="${REPO_STATE[$repo]}"
    branch="${REPO_BRANCH[$repo]:-n/a}"
    stashes="${REPO_STASH_COUNT[$repo]:-0}"
    behind="${REPO_BEHIND[$repo]:-0}"
    ahead="${REPO_AHEAD[$repo]:-0}"
    dirty="${REPO_DIRTY[$repo]:-0}"

    # Color the state
    case "$state" in
        OK) state_color="${GREEN}OK${RESET}" ;;
        STALE) state_color="${YELLOW}STALE${RESET}" ;;
        DIRTY) state_color="${RED}DIRTY${RESET}" ;;
        FEATURE-MERGED) state_color="${CYAN}FEATURE-MERGED${RESET}" ;;
        FEATURE-ACTIVE) state_color="${YELLOW}FEATURE-ACTIVE${RESET}" ;;
        MISSING) state_color="${RED}MISSING${RESET}" ;;
        *) state_color="$state" ;;
    esac

    # Build details string
    details=""
    if [[ "$behind" -gt 0 ]]; then
        details+="↓${behind} "
    fi
    if [[ "$ahead" -gt 0 ]]; then
        details+="↑${ahead} "
    fi
    if [[ "$dirty" -gt 0 ]]; then
        details+="${dirty} uncommitted "
    fi

    # Truncate branch if too long
    if [[ ${#branch} -gt 18 ]]; then
        branch="${branch:0:15}..."
    fi

    printf "%-18s %-26b %-20s %-8s %s\n" "$repo" "$state_color" "$branch" "$stashes" "$details"
done

# Phase 3: Recommendations
echo ""
echo -e "${CYAN}Recommendations:${RESET}"

safe_fixes=0
manual_needed=0

for repo in "${ALL_REPOS[@]}"; do
    state="${REPO_STATE[$repo]}"
    case "$state" in
        OK)
            ;;
        STALE)
            echo -e "  ${GREEN}✓${RESET} $repo: git pull (safe)"
            safe_fixes=$((safe_fixes + 1))
            ;;
        DIRTY)
            echo -e "  ${RED}!${RESET} $repo: has uncommitted changes - review and commit/stash"
            manual_needed=$((manual_needed + 1))
            ;;
        FEATURE-MERGED)
            echo -e "  ${GREEN}✓${RESET} $repo: reset to $CANONICAL_TRUNK_BRANCH (branch already merged)"
            safe_fixes=$((safe_fixes + 1))
            ;;
        FEATURE-ACTIVE)
            echo -e "  ${YELLOW}?${RESET} $repo: on active feature branch - finish work or discard"
            manual_needed=$((manual_needed + 1))
            ;;
        MISSING)
            echo -e "  ${RED}!${RESET} $repo: not cloned at ~/repo"
            manual_needed=$((manual_needed + 1))
            ;;
    esac
done

if [[ $safe_fixes -eq 0 && $manual_needed -eq 0 ]]; then
    echo -e "  ${GREEN}All repos healthy!${RESET}"
fi

echo ""

# Phase 4: Apply fixes if requested
if [[ "$MODE" == "fix" ]]; then
    if [[ $safe_fixes -eq 0 ]]; then
        echo -e "${GREEN}No safe fixes needed.${RESET}"
        exit 0
    fi

    echo -e "${BLUE}Applying safe fixes...${RESET}"
    for repo in "${ALL_REPOS[@]}"; do
        state="${REPO_STATE[$repo]}"
        repo_path="$HOME/$repo"

        case "$state" in
            STALE)
                echo -n "  $repo: pulling... "
                cd "$repo_path"
                if git pull --ff-only origin "$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
                    echo -e "${GREEN}done${RESET}"
                else
                    echo -e "${RED}failed (try manual pull)${RESET}"
                fi
                ;;
            FEATURE-MERGED)
                echo -n "  $repo: resetting to $CANONICAL_TRUNK_BRANCH... "
                cd "$repo_path"
                if git checkout "$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1 && \
                   git pull --ff-only origin "$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
                    echo -e "${GREEN}done${RESET}"
                else
                    echo -e "${RED}failed${RESET}"
                fi
                ;;
        esac
    done
    echo ""
    echo -e "${GREEN}Safe fixes applied.${RESET}"
    if [[ $manual_needed -gt 0 ]]; then
        echo -e "${YELLOW}$manual_needed repo(s) still need manual attention.${RESET}"
    fi

    # Clear triage flags after successful fix
    echo -e "${BLUE}Clearing triage flags...${RESET}"
    for repo in "${ALL_REPOS[@]}"; do
        [[ "${REPO_EXISTS[$repo]:-0}" -eq 0 ]] && continue
        repo_path="$HOME/$repo"
        triage_file="$repo_path/.git/DX_TRIAGE_REQUIRED"
        if [[ -f "$triage_file" ]]; then
            rm -f "$triage_file"
            echo -e "  ${GREEN}✓${RESET} $repo: flag cleared"
        fi
    done

elif [[ "$MODE" == "ack" ]]; then
    echo -e "${BLUE}Acknowledging triage flags...${RESET}"
    echo -e "${YELLOW}This will clear all .git/DX_TRIAGE_REQUIRED flags.${RESET}"
    echo ""

    # Non-interactive: require explicit confirmation via env var
    if [[ "${DX_TRIAGE_ACK_CONFIRM:-}" != "yes" ]]; then
        if [[ -t 0 ]]; then
            read -p "Type 'yes' to confirm: " confirm
            if [[ "$confirm" != "yes" ]]; then
                echo "Aborted."
                exit 1
            fi
        else
            echo "Non-interactive mode. Set DX_TRIAGE_ACK_CONFIRM=yes to proceed."
            exit 1
        fi
    fi

    cleared_count=0
    for repo in "${ALL_REPOS[@]}"; do
        [[ "${REPO_EXISTS[$repo]:-0}" -eq 0 ]] && continue
        repo_path="$HOME/$repo"
        triage_file="$repo_path/.git/DX_TRIAGE_REQUIRED"

        if [[ -f "$triage_file" ]]; then
            # Show what we're acknowledging
            echo ""
            echo -e "${CYAN}$repo:${RESET}"
            cat "$triage_file" | head -8

            # Record acknowledgment in the flag file before clearing
            echo ""
            echo "ACKED_AT: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$triage_file"

            # Move to archive
            archive_dir="$repo_path/.git/dx-triage-archived"
            mkdir -p "$archive_dir"
            mv "$triage_file" "$archive_dir/flag-$(date +%Y%m%d-%H%M%S).txt"

            echo -e "  ${GREEN}✓${RESET} Flag acknowledged and archived"
            cleared_count=$((cleared_count + 1))
        fi
    done

    echo ""
    if [[ $cleared_count -eq 0 ]]; then
        echo -e "${GREEN}No triage flags found.${RESET}"
    else
        echo -e "${GREEN}$cleared_count flag(s) acknowledged and cleared.${RESET}"
        echo -e "${YELLOW}You can now push. Use --no-verify if pre-push hook still blocks.${RESET}"
    fi

elif [[ "$MODE" == "force" ]]; then
    echo -e "${RED}⚠️  FORCE MODE - This will stash WIP and reset ALL repos to $CANONICAL_TRUNK_BRANCH${RESET}"
    echo ""

    # Non-interactive: require explicit confirmation via env var
    if [[ "${DX_TRIAGE_FORCE_CONFIRM:-}" != "yes" ]]; then
        if [[ -t 0 ]]; then
            read -p "Type 'yes' to confirm: " confirm
            if [[ "$confirm" != "yes" ]]; then
                echo "Aborted."
                exit 1
            fi
        else
            echo "Non-interactive mode. Set DX_TRIAGE_FORCE_CONFIRM=yes to proceed."
            exit 1
        fi
    fi

    echo -e "${BLUE}Force resetting all repos...${RESET}"
    for repo in "${ALL_REPOS[@]}"; do
        [[ "${REPO_EXISTS[$repo]:-0}" -eq 0 ]] && continue

        repo_path="$HOME/$repo"
        cd "$repo_path"

        state="${REPO_STATE[$repo]}"
        branch="${REPO_BRANCH[$repo]}"
        dirty="${REPO_DIRTY[$repo]:-0}"

        echo -n "  $repo: "

        # Stash if dirty
        if [[ "$dirty" -gt 0 ]]; then
            echo -n "stashing... "
            git stash push -m "dx-triage force $(date +%Y%m%d-%H%M%S)" >/dev/null 2>&1 || true
        fi

        # Checkout trunk
        if [[ "$branch" != "$CANONICAL_TRUNK_BRANCH" ]]; then
            echo -n "checkout $CANONICAL_TRUNK_BRANCH... "
            git checkout "$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1 || {
                echo -e "${RED}failed${RESET}"
                continue
            }
        fi

        # Reset to origin
        echo -n "reset... "
        git fetch origin >/dev/null 2>&1 || true
        if git reset --hard "origin/$CANONICAL_TRUNK_BRANCH" >/dev/null 2>&1; then
            echo -e "${GREEN}done${RESET}"
        else
            echo -e "${RED}failed${RESET}"
        fi
    done

    echo ""
    echo -e "${GREEN}Force reset complete.${RESET}"
    echo -e "${YELLOW}Note: Check 'git stash list' in each repo for saved WIP.${RESET}"

else
    # Status mode - show what --fix would do
    if [[ $safe_fixes -gt 0 ]]; then
        echo -e "Run ${CYAN}dx-triage --fix${RESET} to apply $safe_fixes safe fix(es)."
    fi
    if [[ $manual_needed -gt 0 ]]; then
        echo -e "${YELLOW}$manual_needed repo(s) need manual attention before --fix can help.${RESET}"
    fi
fi
