#!/usr/bin/env bash
# dx-wip-cleanup.sh
# Clean up old WIP auto-checkpoint branches
#
# Usage:
#   dx-wip-cleanup --dry-run     # Preview what would be deleted
#   dx-wip-cleanup --clean       # Actually delete merged branches
#   dx-wip-cleanup --age=N       # Delete branches older than N days (default: 7)

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

# Default: delete branches older than 7 days
DEFAULT_AGE_DAYS=7
AGE_DAYS="${DEFAULT_AGE_DAYS}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --clean)
            DRY_RUN=0
            shift
            ;;
        --age=*)
            AGE_DAYS="${1#*=}"
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--clean] [--age=N]"
            exit 1
            ;;
    esac
done

# Get current hostname
HOSTNAME=$(hostname -s 2>/dev/null || echo "unknown")

echo "=== WIP Auto-Checkpoint Branch Cleanup ==="
echo "Host: $HOSTNAME"
echo "Age threshold: $AGE_DAYS days"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Mode: DRY RUN (no changes will be made)"
else
    echo "Mode: CLEAN (will delete branches)"
fi
echo ""

# Find WIP branches for this host
WIP_BRANCHES=$(git branch -r 2>/dev/null | grep "wip/auto/${HOSTNAME}/" | sed 's|origin/||' | sed 's| ||g' || true)

if [[ -z "$WIP_BRANCHES" ]]; then
    info "No WIP auto-checkpoint branches found for this host"
    exit 0
fi

# Calculate cutoff date
CUTOFF_DATE=$(date -d "$AGE_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-${AGE_DAYS}d +%Y%m%d 2>/dev/null || date +%Y%m%d)

CANDIDATES_FOR_DELETION=()
BRANCHES_WITH_UNMERGED=()

for branch in $WIP_BRANCHES; do
    # Extract date from branch name (format: wip/auto/HOST/YYYY-MM-DD-HHMMSS)
    BRANCH_DATE=$(echo "$branch" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed 's/-//g' || echo "99999999")

    # Check if branch is older than threshold
    if [[ "$BRANCH_DATE" -lt "$CUTOFF_DATE" ]]; then
        # Check if branch has commits not in master
        if git log master.."origin/$branch" --oneline 2>/dev/null | grep -q .; then
            BRANCHES_WITH_UNMERGED+=("$branch")
        else
            CANDIDATES_FOR_DELETION+=("$branch")
        fi
    fi
done

echo "=== Summary ==="
echo "Total WIP branches: $(echo "$WIP_BRANCHES" | wc -l)"
echo "Older than $AGE_DAYS days: $((${#CANDIDATES_FOR_DELETION[@]} + ${#BRANCHES_WITH_UNMERGED[@]}))"
echo "  - Safe to delete (fully merged): ${#CANDIDATES_FOR_DELETION[@]}"
echo "  - Has unmerged commits: ${#BRANCHES_WITH_UNMERGED[@]}"
echo ""

# Show unmerged branches (these need attention)
if [[ ${#BRANCHES_WITH_UNMERGED[@]} -gt 0 ]]; then
    warn "Branches with UNMERGED commits (need manual review):"
    for branch in "${BRANCHES_WITH_UNMERGED[@]}"; do
        echo "  $branch"
        git log master.."origin/$branch" --oneline 2>/dev/null | head -3 | sed 's/^/    /'
    done
    echo ""
    warn "Action required for unmerged branches:"
    echo "  1. Review commits above"
    echo "  2. Cherry-pick needed commits to master"
    echo "  3. Re-run cleanup after merging"
    echo ""
fi

# Show candidates for deletion
if [[ ${#CANDIDATES_FOR_DELETION[@]} -gt 0 ]]; then
    info "Branches safe to delete (fully merged to master):"
    for branch in "${CANDIDATES_FOR_DELETION[@]}"; do
        echo "  $branch"
    done
    echo ""
fi

# Delete merged branches if not dry-run
if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run complete. Use --clean to actually delete branches."
elif [[ ${#CANDIDATES_FOR_DELETION[@]} -gt 0 ]]; then
    info "Deleting merged branches..."
    DELETED=0
    for branch in "${CANDIDATES_FOR_DELETION[@]}"; do
        if git push origin --delete "$branch" >/dev/null 2>&1; then
            success "Deleted: $branch"
            DELETED=$((DELETED + 1))
        else
            # Try local branch delete (might not exist locally)
            git branch -D "$branch" 2>/dev/null || true
            warn "Failed to delete remote: $branch (may already be gone)"
        fi
    done
    echo ""
    success "Deleted $DELETED branches"
else
    info "No branches to delete"
fi

if [[ ${#BRANCHES_WITH_UNMERGED[@]} -gt 0 ]]; then
    exit 1
fi
