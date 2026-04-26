#!/bin/sh

set -eu

export PGDATA="$HOME/ymy46"
export PGPORT="9530"

BACKUP_HOST="backup_pg121"
REMOTE_DIR="/var/db/postgres4/pg_backups/sql_dump"

DATE_TAG="$(date '+%Y-%m-%d_%H-%M-%S')"
BACKUP_NAME="pg111_full_cluster_${DATE_TAG}.sql.gz"

LOG_DIR="$HOME/backup_logs"
LOG_FILE="$LOG_DIR/backup_sql_dump.log"

mkdir -p "$LOG_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] backup started: ${BACKUP_NAME}" >> "$LOG_FILE"

pg_ctl -D "$PGDATA" status >> "$LOG_FILE" 2>&1

ssh "$BACKUP_HOST" "mkdir -p '$REMOTE_DIR' && chmod 700 '$REMOTE_DIR'"

pg_dumpall -p "$PGPORT" \
  | gzip -9 \
  | ssh "$BACKUP_HOST" "cat > '$REMOTE_DIR/${BACKUP_NAME}.tmp' && mv '$REMOTE_DIR/${BACKUP_NAME}.tmp' '$REMOTE_DIR/${BACKUP_NAME}'"

ssh "$BACKUP_HOST" "find '$REMOTE_DIR' -type f -name 'pg111_full_cluster_*.sql.gz' -mtime +28 -delete"

ssh "$BACKUP_HOST" "ls -lh '$REMOTE_DIR/${BACKUP_NAME}'" >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] backup finished: ${BACKUP_NAME}" >> "$LOG_FILE"
