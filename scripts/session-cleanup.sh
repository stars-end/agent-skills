#!/bin/bash
# session-cleanup.sh
# Cleanup worktrees after session completion
# Usage: session-cleanup.sh [--all] [--beads-id <id>] [--older-than <days>] [--dry-run]

set -e

WORKTREE_BASE="${WORKTREE_BASE:-/tmp/agents}"
DRY_RUN=false
VERBOSE=false
CLEAN_MODE="all"  # all, beads-id, older-than

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --all)
            CLEAN_MODE="all"
            shift
            ;;
        --beads-id)
            CLEAN_MODE="beads-id"
            BEADS_ID="$2"
            shift 2
            ;;
        --older-than)
            CLEAN_MODE="older-than"
            OLDER_THAN_DAYS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Cleanup worktrees after session completion."
            echo ""
            echo "Options:"
            echo "  --all              Clean up all worktrees (default)"
            echo "  --beads-id <id>    Clean up worktrees for specific beads ID"
            echo "  --older-than <d>   Clean up worktrees older than N days"
            echo "  --dry-run          Show what would be deleted without deleting"
            echo "  --verbose,-v       Show detailed progress"
            echo "  --help,-h          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --all                    # Clean up all worktrees"
            echo "  $0 --beads-id bd-123        # Clean up bd-123 worktrees"
            echo "  $0 --older-than 7           # Clean up worktrees >7 days old"
            echo "  $0 --all --dry-run          # Preview cleanup"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "[VERBOSE] $1"
    fi
}

log_warn() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Check if worktree base directory exists
if [ ! -d "$WORKTREE_BASE" ]; then
    log_info "Worktree base directory not found: $WORKTREE_BASE"
    exit 0
fi

log_info "=== Session Worktree Cleanup ==="
log_info "Worktree base: $WORKTREE_BASE"
log_info "Cleanup mode: $CLEAN_MODE"

# Collect directories to clean
DIRECTORIES_TO_REMOVE=""

case "$CLEAN_MODE" in
    "all")
        log_info "Collecting all worktree directories..."
        for dir in "$WORKTREE_BASE"/*; do
            if [ -d "$dir" ]; then
                DIRECTORIES_TO_REMOVE="$DIRECTORIES_TO_REMOVE $dir"
            fi
        done
        ;;
    "beads-id")
        if [ -z "$BEADS_ID" ]; then
            log_error "Missing beads-id argument"
            exit 1
        fi
        log_info "Collecting worktrees for beads ID: $BEADS_ID"
        if [ -d "$WORKTREE_BASE/$BEADS_ID" ]; then
            DIRECTORIES_TO_REMOVE="$WORKTREE_BASE/$BEADS_ID"
        else
            log_info "No worktrees found for $BEADS_ID"
            exit 0
        fi
        ;;
    "older-than")
        if [ -z "$OLDER_THAN_DAYS" ]; then
            log_error "Missing older-than argument"
            exit 1
        fi
        log_info "Collecting worktrees older than $OLDER_THAN_DAYS days..."
        CUTOFF_TIME=$(($(date +%s) - (OLDER_THAN_DAYS * 86400)))
        for dir in "$WORKTREE_BASE"/*; do
            if [ -d "$dir" ]; then
                DIR_TIME=$(stat -f %m "$dir" 2>/dev/null || stat -c %Y "$dir" 2>/dev/null || echo 0)
                if [ "$DIR_TIME" -lt "$CUTOFF_TIME" ]; then
                    DIRECTORIES_TO_REMOVE="$DIRECTORIES_TO_REMOVE $dir"
                    log_verbose "  Found old directory: $dir ($(date -r $DIR_TIME '+%Y-%m-%d %H:%M:%S'))"
                fi
            fi
        done
        ;;
esac

# Trim leading space
DIRECTORIES_TO_REMOVE=$(echo "$DIRECTORIES_TO_REMOVE" | sed 's/^ //')

# Check if there's anything to clean
if [ -z "$DIRECTORIES_TO_REMOVE" ]; then
    log_info "No worktrees to clean up"
    exit 0
fi

# Count directories
DIR_COUNT=$(echo "$DIRECTORIES_TO_REMOVE" | wc -w | tr -d ' ')
log_info "Found $DIR_COUNT director(y/ies) to clean up"

# Show what will be removed
log_info "Directories to remove:"
for dir in $DIRECTORIES_TO_REMOVE; do
    log_info "  - $(basename "$dir")"
done

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] No files were deleted"
    exit 0
fi

# Confirmation prompt
echo ""
read -p "Remove $DIR_COUNT director(y/ies)? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

# Perform cleanup
log_info "Starting cleanup..."
REMOVED_COUNT=0
FAILED_COUNT=0

for dir in $DIRECTORIES_TO_REMOVE; do
    dir_name=$(basename "$dir")
    log_verbose "Processing: $dir_name"

    # Prune git worktree metadata if inside a worktree
    if [ -d "$dir" ]; then
        # Find all .git files (worktree markers) and prune them
        find "$dir" -name ".git" -type f 2>/dev/null | while read gitfile; do
            worktree_dir=$(dirname "$gitfile")
            log_verbose "  Pruning worktree: $worktree_dir"
            cd "$worktree_dir" 2>/dev/null && git worktree prune 2>/dev/null || true
        done

        # Remove the directory
        if rm -rf "$dir"; then
            log_verbose "  ✓ Removed: $dir_name"
            ((REMOVED_COUNT++))
        else
            log_error "  ✗ Failed to remove: $dir_name"
            ((FAILED_COUNT++))
        fi
    fi
done

# Prune git worktree metadata from all canonical repos
log_info "Pruning worktree metadata from canonical repos..."
for repo in "$HOME"/agent-skills "$HOME"/prime-radiant-ai "$HOME"/affordabot "$HOME"/llm-common; do
    if [ -d "$repo/.git" ]; then
        log_verbose "Pruning: $repo"
        git -C "$repo" worktree prune 2>/dev/null || true
    fi
done

# Summary
log_info "=== Cleanup Complete ==="
log_info "Removed: $REMOVED_COUNT"
if [ $FAILED_COUNT -gt 0 ]; then
    log_warn "Failed: $FAILED_COUNT"
fi

if [ $FAILED_COUNT -eq 0 ]; then
    exit 0
else
    exit 1
fi

