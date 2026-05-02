cat > "$HOME/scripts/restore_after_tablespace_loss.sh" <<'EOF'
#!/bin/sh

set -eu

# Сценарий предполагает, что директория табличного пространства idxspace была удалена,
# а резервная копия SQL Dump хранится на резервном узле pg121.

OLD_PGDATA="$HOME/ymy46"

export PGDATA="$HOME/ymy46_stage3_restored"
export PGPORT="9530"
export PGDATABASE="fastorangecity"

PGWAL="$HOME/xlg69_stage3_restored"
NEW_TABLESPACE_DIR="$HOME/mgg73_stage3_restored"

BACKUP_HOST="backup_pg121"
BACKUP_DIR_REMOTE="/var/db/postgres4/pg_backups/sql_dump"

OLD_TABLESPACE_PATH="/var/db/postgres3/mgg73"
NEW_TABLESPACE_PATH="/var/db/postgres3/mgg73_stage3_restored"

LOG_DIR="$HOME/recovery_logs"
LOG_FILE="$LOG_DIR/stage3_restore.log"

mkdir -p "$LOG_DIR"

echo "=== Stage 3 restore started at $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$LOG_FILE"

echo "=== Stop damaged old cluster if it is running ===" | tee -a "$LOG_FILE"
if [ -d "$OLD_PGDATA" ]; then
    if pg_ctl -D "$OLD_PGDATA" status >/dev/null 2>&1; then
        pg_ctl -D "$OLD_PGDATA" stop -m fast | tee -a "$LOG_FILE"
    else
        echo "Old cluster is not running" | tee -a "$LOG_FILE"
    fi
else
    echo "Old PGDATA does not exist: $OLD_PGDATA" | tee -a "$LOG_FILE"
fi

echo "=== Find latest backup on reserve node ===" | tee -a "$LOG_FILE"
LATEST_BACKUP="$(ssh "$BACKUP_HOST" "ls -t $BACKUP_DIR_REMOTE/pg111_full_cluster_*.sql.gz | head -n 1")"
echo "Latest backup: $LATEST_BACKUP" | tee -a "$LOG_FILE"

echo "=== Check backup archive integrity ===" | tee -a "$LOG_FILE"
ssh "$BACKUP_HOST" "gzip -t '$LATEST_BACKUP' && echo OK" | tee -a "$LOG_FILE"

echo "=== Recreate recovery directories ===" | tee -a "$LOG_FILE"
rm -rf "$PGDATA" "$PGWAL" "$NEW_TABLESPACE_DIR"
mkdir -p "$PGWAL" "$NEW_TABLESPACE_DIR"
chmod 700 "$PGWAL" "$NEW_TABLESPACE_DIR"

ls -ld "$PGWAL" "$NEW_TABLESPACE_DIR" | tee -a "$LOG_FILE"

echo "=== Initialize new PostgreSQL cluster ===" | tee -a "$LOG_FILE"
initdb -D "$PGDATA" \
  -X "$PGWAL" \
  --locale=ru_RU.CP1251 \
  --encoding=WIN1251 | tee -a "$LOG_FILE"

echo "=== Configure postgresql.conf ===" | tee -a "$LOG_FILE"
cat >> "$PGDATA/postgresql.conf" <<'CONFEOF'

# Настройки восстановленного экземпляра для этапа 3
listen_addresses = 'localhost'
port = 9530

max_connections = 30
shared_buffers = 2GB
temp_buffers = 32MB
work_mem = 64MB
checkpoint_timeout = 15min
effective_cache_size = 18GB
fsync = on
commit_delay = 10000

logging_collector = on
log_destination = 'stderr'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_min_messages = notice
log_connections = on
log_checkpoints = on
CONFEOF

echo "=== Configure pg_hba.conf ===" | tee -a "$LOG_FILE"
cat > "$PGDATA/pg_hba.conf" <<'HBAEOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Unix-domain socket
local   all             all                                     peer

# TCP/IP only from localhost
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust

# Reject everything else
host    all             all             0.0.0.0/0               reject
host    all             all             ::0/0                   reject
HBAEOF

echo "=== Start restored empty cluster ===" | tee -a "$LOG_FILE"
pg_ctl -D "$PGDATA" start | tee -a "$LOG_FILE"
pg_ctl -D "$PGDATA" status | tee -a "$LOG_FILE"

echo "=== Check connection to postgres database ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d postgres -c '\conninfo' | tee -a "$LOG_FILE"

echo "=== Check old tablespace path inside backup ===" | tee -a "$LOG_FILE"
ssh "$BACKUP_HOST" "gzip -dc '$LATEST_BACKUP' | grep -n \"CREATE TABLESPACE\\|$OLD_TABLESPACE_PATH\" | head -n 20" | tee -a "$LOG_FILE" || true

echo "=== Restore SQL Dump with corrected tablespace path ===" | tee -a "$LOG_FILE"
ssh "$BACKUP_HOST" "gzip -dc '$LATEST_BACKUP'" \
  | sed \
      -e "s|$OLD_TABLESPACE_PATH|$NEW_TABLESPACE_PATH|g" \
      -e "/^CREATE ROLE postgres3;$/d" \
      -e "/^ALTER ROLE postgres3 /d" \
  | psql -p "$PGPORT" -d postgres -v ON_ERROR_STOP=1 | tee -a "$LOG_FILE"

echo "=== Check databases ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d postgres -c '\l' | tee -a "$LOG_FILE"

echo "=== Check tablespaces ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d postgres -c '\db' | tee -a "$LOG_FILE"

echo "=== Check connection to restored database ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d fastorangecity -c '\conninfo' | tee -a "$LOG_FILE"

echo "=== Check restored tables ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d fastorangecity -c '\dt' | tee -a "$LOG_FILE"

echo "=== Check row counts ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d fastorangecity -c "
SELECT 'clients' AS table_name, count(*) FROM clients
UNION ALL
SELECT 'branches', count(*) FROM branches
UNION ALL
SELECT 'accounts', count(*) FROM accounts
UNION ALL
SELECT 'operations', count(*) FROM operations;
" | tee -a "$LOG_FILE"

echo "=== Check previously broken index access ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d fastorangecity -c "
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT * FROM accounts WHERE client_id = 1;
" | tee -a "$LOG_FILE"

echo "=== Stage 3 restore finished successfully at $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$LOG_FILE"
EOF

chmod +x "$HOME/scripts/restore_after_tablespace_loss.sh"