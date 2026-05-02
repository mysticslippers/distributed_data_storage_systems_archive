mkdir -p "$HOME/scripts"

cat > "$HOME/scripts/restore_after_logical_error_pitr.sh" <<'EOF'
#!/bin/sh

set -eu

# Сценарий предполагает, что:
# 1) архивирование WAL уже было включено;
# 2) физическая базовая копия уже создана;
# 3) recovery_target_time уже известен;
# 4) ошибочная операция DROP TABLE уже была выполнена.

export PGPORT="9530"
export PGDATABASE="fastorangecity"

# Повреждённый рабочий кластер после DROP TABLE
DAMAGED_PGDATA="$HOME/ymy46_stage3_restored"

# Каталог архивных WAL
ARCHIVE_DIR="$HOME/wal_archive_stage4"

# Физическая базовая копия, созданная до добавления строк и DROP TABLE
BASE_COPY_DIR="$HOME/stage4_basecopy"
BASE_PGDATA="$BASE_COPY_DIR/ymy46_base"
BASE_PGWAL="$BASE_COPY_DIR/xlg69_base"
BASE_TABLESPACE_DIR="$BASE_COPY_DIR/mgg73_base"

# Каталоги восстановленного экземпляра
RESTORE_PGDATA="$HOME/ymy46_stage4_restored"
RESTORE_PGWAL="$HOME/xlg69_stage4_restored"
RESTORE_TABLESPACE_DIR="$HOME/mgg73_stage4_restored"

# OID пользовательского табличного пространства в pg_tblspc
TABLESPACE_OID="16385"

# Точка восстановления: после INSERT, но до DROP TABLE
RECOVERY_TARGET_TIME="2026-05-01 14:37:58.468081+03"

LOG_DIR="$HOME/recovery_logs"
LOG_FILE="$LOG_DIR/stage4_pitr_restore.log"

mkdir -p "$LOG_DIR"

echo "=== Stage 4 PITR restore started at $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$LOG_FILE"

echo "=== Check required source directories ===" | tee -a "$LOG_FILE"
for dir in "$BASE_PGDATA" "$BASE_PGWAL" "$BASE_TABLESPACE_DIR" "$ARCHIVE_DIR"; do
    if [ ! -e "$dir" ]; then
        echo "Required path does not exist: $dir" | tee -a "$LOG_FILE"
        exit 1
    fi
    ls -ld "$dir" | tee -a "$LOG_FILE"
done

echo "=== Stop damaged cluster if it is running ===" | tee -a "$LOG_FILE"
if [ -d "$DAMAGED_PGDATA" ]; then
    if pg_ctl -D "$DAMAGED_PGDATA" status >/dev/null 2>&1; then
        pg_ctl -D "$DAMAGED_PGDATA" stop -m fast | tee -a "$LOG_FILE"
    else
        echo "Damaged cluster is not running" | tee -a "$LOG_FILE"
    fi
else
    echo "Damaged PGDATA does not exist: $DAMAGED_PGDATA" | tee -a "$LOG_FILE"
fi

echo "=== Recreate restore directories from base copy ===" | tee -a "$LOG_FILE"
rm -rf "$RESTORE_PGDATA" "$RESTORE_PGWAL" "$RESTORE_TABLESPACE_DIR"

cp -a "$BASE_PGDATA" "$RESTORE_PGDATA"
cp -a "$BASE_PGWAL" "$RESTORE_PGWAL"
cp -a "$BASE_TABLESPACE_DIR" "$RESTORE_TABLESPACE_DIR"

ls -ld "$RESTORE_PGDATA" "$RESTORE_PGWAL" "$RESTORE_TABLESPACE_DIR" | tee -a "$LOG_FILE"

echo "=== Fix symbolic links for WAL and tablespace ===" | tee -a "$LOG_FILE"

rm -rf "$RESTORE_PGDATA/pg_wal"
ln -s "$RESTORE_PGWAL" "$RESTORE_PGDATA/pg_wal"

rm -f "$RESTORE_PGDATA/pg_tblspc/$TABLESPACE_OID"
ln -s "$RESTORE_TABLESPACE_DIR" "$RESTORE_PGDATA/pg_tblspc/$TABLESPACE_OID"

ls -l "$RESTORE_PGDATA/pg_wal" | tee -a "$LOG_FILE"
ls -l "$RESTORE_PGDATA/pg_tblspc" | tee -a "$LOG_FILE"

echo "=== Configure PITR recovery ===" | tee -a "$LOG_FILE"

rm -f "$RESTORE_PGDATA/recovery.signal"
touch "$RESTORE_PGDATA/recovery.signal"

cat >> "$RESTORE_PGDATA/postgresql.conf" <<CONFEOF

# Настройки восстановления PITR для этапа 4
restore_command = 'cp $ARCHIVE_DIR/%f %p'
recovery_target_time = '$RECOVERY_TARGET_TIME'
recovery_target_action = 'promote'
CONFEOF

echo "restore_command = 'cp $ARCHIVE_DIR/%f %p'" | tee -a "$LOG_FILE"
echo "recovery_target_time = '$RECOVERY_TARGET_TIME'" | tee -a "$LOG_FILE"
echo "recovery_target_action = 'promote'" | tee -a "$LOG_FILE"

echo "=== Start restored cluster ===" | tee -a "$LOG_FILE"
pg_ctl -D "$RESTORE_PGDATA" start | tee -a "$LOG_FILE"

echo "=== Check restored cluster status ===" | tee -a "$LOG_FILE"
pg_ctl -D "$RESTORE_PGDATA" status | tee -a "$LOG_FILE"

echo "=== Check connection ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d "$PGDATABASE" -c '\conninfo' | tee -a "$LOG_FILE"

echo "=== Check restored tables ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d "$PGDATABASE" -c '\dt' | tee -a "$LOG_FILE"

echo "=== Check row counts ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d "$PGDATABASE" -c "
SELECT 'clients' AS table_name, count(*) FROM clients
UNION ALL
SELECT 'branches', count(*) FROM branches
UNION ALL
SELECT 'accounts', count(*) FROM accounts
UNION ALL
SELECT 'operations', count(*) FROM operations;
" | tee -a "$LOG_FILE"

echo "=== Check rows added before DROP TABLE ===" | tee -a "$LOG_FILE"
psql -p "$PGPORT" -d "$PGDATABASE" -c "
SELECT *
FROM clients
WHERE client_id IN (4, 5);
" | tee -a "$LOG_FILE"

psql -p "$PGPORT" -d "$PGDATABASE" -c "
SELECT *
FROM operations
WHERE operation_id IN (5, 6);
" | tee -a "$LOG_FILE"

echo "=== Show recovery log tail ===" | tee -a "$LOG_FILE"
tail -n 80 "$RESTORE_PGDATA"/log/*.log | tee -a "$LOG_FILE"

echo "=== Stage 4 PITR restore finished successfully at $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$LOG_FILE"
EOF

chmod +x "$HOME/scripts/restore_after_logical_error_pitr.sh"