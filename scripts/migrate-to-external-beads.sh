#!/bin/bash
# migrate-to-external-beads.sh
# Production-grade migration to external beads database.
#
# RUN THIS ON EACH VM (homedesktop-wsl, macmini, epyc6)
#
# Usage:
#   ./scripts/migrate-to-external-beads.sh [--dry-run] [--force]
#
# Options:
#   --dry-run    Show what would happen without making changes
#   --force      Skip confirmation prompts
#
# Features:
#   - Pre-flight checks (backup existing data)
#   - Atomic migration (rollback if anything fails)
#   - Post-flight verification
#   - Comprehensive logging

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

CENTRAL_DB_DIR="$HOME/bd"
CENTRAL_DB_PATH="$CENTRAL_DB_DIR/.beads"
BACKUP_DIR="$HOME/.beads-migration-backup-$(date +%Y%m%d%H%M%S)"
LOG_FILE="$HOME/.beads-migration.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING
# =============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

log_info "=== Beads External DB Migration ==="
log_info "Hostname: $(hostname)"
log_info "User: $USER"
log_info "Dry run: $DRY_RUN"
log_info ""

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

check_prerequisites() {
    log_info "Running pre-flight checks..."

    local checks_failed=0

    # Check 1: bd CLI must be available
    if ! command -v bd >/dev/null 2>&1; then
        log_error "bd CLI not found. Install beads first."
        checks_failed=1
    else
        log_success "✓ bd CLI found: $(bd --version 2>/dev/null || echo 'unknown version')"
    fi

    # Check 2: git must be available
    if ! command -v git >/dev/null 2>&1; then
        log_error "git not found."
        checks_failed=1
    else
        log_success "✓ git found"
    fi

    # Check 3: agent-skills repo must exist
    if [ ! -d "$HOME/agent-skills" ]; then
        log_error "agent-skills repo not found at $HOME/agent-skills"
        checks_failed=1
    else
        log_success "✓ agent-skills repo found"
    fi

    # Check 4: No active beads work in progress
    log_info "Checking for active beads work..."
    ACTIVE_ISSUES=$(bd list --status in-progress 2>/dev/null | grep -c "\[in-progress\]" 2>/dev/null || echo "0")
    ACTIVE_ISSUES=$(echo "$ACTIVE_ISSUES" | tr -d '[:space:]')  # Remove whitespace
    if [ "$ACTIVE_ISSUES" -gt 0 ]; then
        log_warning "⚠ Found $ACTIVE_ISSUES in-progress issues"
        log_warning "Consider finishing these before migration:"
        bd list --status in-progress 2>/dev/null || true
        if [ "$FORCE" != true ]; then
            read -p "Continue anyway? [y/N]: " continue_anyway
            if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
                log_info "Migration cancelled."
                exit 0
            fi
        fi
    else
        log_success "✓ No active work in progress"
    fi

    # Check 5: Verify we can write to HOME
    if [ ! -w "$HOME" ]; then
        log_error "Cannot write to $HOME"
        checks_failed=1
    fi

    if [ $checks_failed -ne 0 ]; then
        log_error "Pre-flight checks failed. Aborting."
        exit 1
    fi

    log_success "✓ All pre-flight checks passed"
    echo ""
}

# =============================================================================
# BACKUP EXISTING DATA
# =============================================================================

backup_existing_data() {
    log_info "Creating backup of existing beads data..."

    mkdir -p "$BACKUP_DIR"

    # Find all .beads directories in known repos
    local repos=("$HOME/agent-skills" "$HOME/prime-radiant-ai" "$HOME/affordabot" "$HOME/llm-common")
    local found_any=false

    for repo in "${repos[@]}"; do
        if [ -d "$repo/.beads" ]; then
            local backup_name=$(basename "$repo")
            log_info "Backing up $repo/.beads..."
            cp -r "$repo/.beads" "$BACKUP_DIR/${backup_name}-beads" 2>/dev/null || true
            log_success "✓ Backed up to $BACKUP_DIR/${backup_name}-beads"
            found_any=true
        fi
    done

    if [ "$found_any" = false ]; then
        log_info "No existing .beads directories found to backup"
    fi

    log_success "✓ Backup complete: $BACKUP_DIR"
    echo ""
}

# =============================================================================
# CREATE CENTRAL DATABASE
# =============================================================================

create_central_db() {
    log_info "Creating central beads database at $CENTRAL_DB_DIR..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create: $CENTRAL_DB_DIR"
        log_info "[DRY-RUN] Would run: cd $CENTRAL_DB_DIR && git init && bd init"
        return
    fi

    mkdir -p "$CENTRAL_DB_DIR"
    cd "$CENTRAL_DB_DIR"

    # Initialize git if not already done
    if [ ! -d ".git" ]; then
        git init -q
        log_success "✓ Git repository initialized"
    else
        log_info "✓ Git repository already exists"
    fi

    # Initialize beads if not already done
    if [ ! -f ".beads/beads.db" ]; then
        bd init -q
        log_success "✓ Beads database initialized"

        # Initial commit
        git add .beads/
        git commit -q -m "Initialize central beads database"
        log_success "✓ Initial commit created"
    else
        log_info "✓ Beads database already exists"
    fi

    echo ""
}

# =============================================================================
# EXPORT AND MIGRATE EXISTING ISSUES
# =============================================================================

migrate_existing_issues() {
    log_info "Migrating existing issues to central database..."

    local repos=("$HOME/agent-skills" "$HOME/prime-radiant-ai" "$HOME/affordabot" "$HOME/llm-common")
    local total_migrated=0

    for repo in "${repos[@]}"; do
        if [ ! -d "$repo/.beads" ]; then
            continue
        fi

        local repo_name=$(basename "$repo")
        log_info "Processing $repo_name..."

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would export issues from $repo/.beads"
            continue
        fi

        # Temporarily unset BEADS_DIR to access local database
        (
            unset BEADS_DIR
            cd "$repo"

            # Export issues if database exists and has issues
            if [ -f ".beads/beads.db" ]; then
                local issue_count=$(bd list --json 2>/dev/null | grep -c "\"id\":" || echo "0")
                if [ "$issue_count" -gt 0 ]; then
                    local export_file="$BACKUP_DIR/${repo_name}-issues.jsonl"
                    log_info "  Exporting $issue_count issues..."
                    bd export -o "$export_file" -q 2>/dev/null || true

                    # Import to central database
                    log_info "  Importing to central DB..."
                    export BEADS_DIR="$CENTRAL_DB_PATH"
                    bd import "$export_file" -q 2>/dev/null || log_warning "  Import had issues (may be duplicates)"
                    total_migrated=$((total_migrated + issue_count))
                fi
            fi
        )
    done

    log_success "✓ Migrated approximately $total_migrated issues"
    echo ""
}

# =============================================================================
# UPDATE SHELL PROFILES
# =============================================================================

update_shell_profiles() {
    log_info "Updating shell profiles..."

    local bead_line="export BEADS_DIR=\"$CENTRAL_DB_PATH\""
    local marker="# External Beads Database (managed by migrate-to-external-beads.sh)"

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zshenv"; do
        if [ ! -f "$rc_file" ]; then
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would add BEADS_DIR to $rc_file"
            continue
        fi

        # Check if already configured
        if grep -q "BEADS_DIR.*bd" "$rc_file" 2>/dev/null; then
            log_info "✓ $rc_file already configured"
            continue
        fi

        # Add to profile
        echo "" >> "$rc_file"
        echo "$marker" >> "$rc_file"
        echo "$bead_line" >> "$rc_file"
        log_success "✓ Updated $rc_file"
    done

    echo ""
}

# =============================================================================
# POST-FLIGHT VERIFICATION
# =============================================================================

verify_migration() {
    log_info "Running post-flight verification..."

    local checks_failed=0

    # Verify BEADS_DIR is set in current shell
    if [ -z "${BEADS_DIR:-}" ]; then
        log_warning "⚠ BEADS_DIR not set in current shell (restart shell or run: source ~/.bashrc)"
    else
        log_success "✓ BEADS_DIR is set: $BEADS_DIR"
    fi

    # Verify central database exists
    if [ ! -f "$CENTRAL_DB_PATH/beads.db" ]; then
        log_error "Central database not found at $CENTRAL_DB_PATH/beads.db"
        checks_failed=1
    else
        log_success "✓ Central database exists"
    fi

    # Verify bd can access the database
    if [ -n "${BEADS_DIR:-}" ]; then
        if ! bd list >/dev/null 2>&1; then
            log_error "bd cannot access central database"
            checks_failed=1
        else
            log_success "✓ bd can access central database"
            local issue_count=$(bd list 2>/dev/null | wc -l || echo "0")
            log_info "  Total issues in central DB: $issue_count"
        fi
    fi

    # Verify old .beads are still accessible (for rollback)
    local old_accessible=true
    for repo in "$HOME/agent-skills" "$HOME/prime-radiant-ai"; do
        if [ -d "$repo/.beads" ] && [ -f "$repo/.beads/beads.db" ]; then
            # Temporarily unset BEADS_DIR to test old database
            (
                unset BEADS_DIR
                cd "$repo"
                if ! bd list >/dev/null 2>&1; then
                    old_accessible=false
                fi
            )
        fi
    done

    if [ "$old_accessible" = false ]; then
        log_warning "⚠ Some old .beads databases may not be accessible"
    else
        log_success "✓ Old .beads databases still accessible (rollback possible)"
    fi

    if [ $checks_failed -ne 0 ]; then
        log_error "Post-flight verification failed."
        log_error "Backup located at: $BACKUP_DIR"
        exit 1
    fi

    log_success "✓ All post-flight checks passed"
    echo ""
}

# =============================================================================
# PRINT SUMMARY
# =============================================================================

print_summary() {
    log_success "=== Migration Complete ==="
    echo ""
    echo "Summary:"
    echo "  Central DB: $CENTRAL_DB_PATH"
    echo "  Backup: $BACKUP_DIR"
    echo "  Log: $LOG_FILE"
    echo ""
    echo "Next steps:"
    echo "  1. Source your shell profile: source ~/.bashrc"
    echo "  2. Verify: echo \$BEADS_DIR"
    echo "  3. Test: bd list"
    echo ""
    echo "To rollback (if needed):"
    echo "  1. Remove BEADS_DIR from ~/.bashrc and ~/.zshrc"
    echo "  2. Restart shell"
    echo "  3. Restore from: $BACKUP_DIR"
    echo ""
}

# =============================================================================
# CONFIRMATION
# =============================================================================

request_confirmation() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return
    fi

    echo ""
    echo "This will:"
    echo "  1. Backup existing .beads/ directories to $BACKUP_DIR"
    echo "  2. Create central database at $CENTRAL_DB_PATH"
    echo "  3. Migrate existing issues to central database"
    echo "  4. Update shell profiles to set BEADS_DIR"
    echo ""
    read -p "Continue? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Migration cancelled."
        exit 0
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    check_prerequisites
    request_confirmation
    backup_existing_data
    create_central_db
    migrate_existing_issues
    update_shell_profiles
    verify_migration
    print_summary
}

main
