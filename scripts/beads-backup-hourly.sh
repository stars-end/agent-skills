#!/usr/bin/env bash
# beads-backup-hourly.sh - Hourly Dolt snapshot backup to MinIO
# Runs on: epyc12 (hub)
# Schedule: Hourly via cron

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_DIR=$(date +%Y%m%d)
BEADS_REPO="${BEADS_REPO_PATH:-$HOME/bd}"
DOLT_DIR="$BEADS_REPO/.beads/dolt"
BACKUP_NAME="beads_dolt_${TIMESTAMP}"
MINIO_ALIAS="${MINIO_ALIAS:-beads-minio}"
MINIO_BUCKET="${MINIO_BUCKET:-beads-backups}"
RETENTION_DAYS=7

log() {
  echo "[$(date -Iseconds)] $*"
}

error() {
  echo "[$(date -Iseconds)] ERROR: $*" >&2
}

check_prerequisites() {
  if [[ ! -d "$DOLT_DIR" ]]; then
    error "Dolt data directory not found: $DOLT_DIR"
    exit 1
  fi

  if ! command -v mc &>/dev/null; then
    error "MinIO client (mc) not found"
    exit 1
  fi

  if ! mc alias list 2>/dev/null | grep -q "^$MINIO_ALIAS"; then
    error "MinIO alias '$MINIO_ALIAS' not configured"
    exit 1
  fi
}

create_backup() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf $tmp_dir" EXIT

  log "Creating backup: $BACKUP_NAME"

  # Create schema dump using dolt
  cd "$BEADS_REPO"
  if ! dolt dump --dump-format sql > "$tmp_dir/schema.sql" 2>/dev/null; then
    # Fallback: tar the entire dolt directory
    log "Schema dump failed, using tar archive"
    tar -C "$DOLT_DIR" -czf "$tmp_dir/${BACKUP_NAME}.tar.gz" .
    local backup_file="$tmp_dir/${BACKUP_NAME}.tar.gz"
  else
    # Also include full dolt directory for complete restore
    tar -C "$DOLT_DIR" -czf "$tmp_dir/dolt_data.tar.gz" .
    
    # Create combined archive
    tar -C "$tmp_dir" -czf "$tmp_dir/${BACKUP_NAME}.tar.gz" schema.sql dolt_data.tar.gz
    local backup_file="$tmp_dir/${BACKUP_NAME}.tar.gz"
  fi

  # Upload to MinIO
  local minio_path="$MINIO_ALIAS/$MINIO_BUCKET/$DATE_DIR"
  if ! mc mkdir "$minio_path" 2>/dev/null; then
    log "Note: Could not create bucket path (may already exist)"
  fi

  if mc cp "$backup_file" "$minio_path/${BACKUP_NAME}.tar.gz"; then
    log "Backup uploaded successfully: $minio_path/${BACKUP_NAME}.tar.gz"
  else
    error "Failed to upload backup to MinIO"
    exit 1
  fi
}

rotate_old_backups() {
  log "Rotating backups older than $RETENTION_DAYS days"
  
  local cutoff_date
  cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y%m%d)

  # List and remove old backup directories
  mc ls "$MINIO_ALIAS/$MINIO_BUCKET/" 2>/dev/null | while read -r line; do
    local dir_date
    dir_date=$(echo "$line" | grep -oE '[0-9]{8}' | head -1)
    if [[ -n "$dir_date" && "$dir_date" < "$cutoff_date" ]]; then
      log "Removing old backup: $dir_date"
      mc rm -r --force "$MINIO_ALIAS/$MINIO_BUCKET/$dir_date" 2>/dev/null || true
    fi
  done
}

verify_backup() {
  log "Verifying latest backup exists"
  local latest
  latest=$(mc ls "$MINIO_ALIAS/$MINIO_BUCKET/$DATE_DIR/" 2>/dev/null | tail -1)
  if [[ -z "$latest" ]]; then
    error "No backup found in MinIO"
    exit 1
  fi
  log "Latest backup: $latest"
}

main() {
  log "=== Starting Beads hourly backup ==="
  check_prerequisites
  create_backup
  rotate_old_backups
  verify_backup
  log "=== Backup complete ==="
}

main "$@"
