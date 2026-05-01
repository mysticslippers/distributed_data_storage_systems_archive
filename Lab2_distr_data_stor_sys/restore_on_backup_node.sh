mkdir -p "$HOME/scripts"

cat > "$HOME/scripts/restore_on_backup_node.sh" <<'EOF'
#!/bin/sh

set -eu

# Этап 2: восстановление работы СУБД на резервном узле pg121
# Сценарий предполагает, что SQL Dump-архив уже находится на резервном узле.

export PGDATA="$HOME/ymy46_restored"
export PGPORT="9530"
export PGDATABASE="fastorangecity"

PGWAL="$HOME/xlg69_restored"
BACKUP_DIR="$HOME/pg_backups/sql_dump"
TABLESPACE_DIR="$HOME/mgg73"

OLD_TABLESPACE_PATH="/var/db/postgres3/mgg73"
NEW_TABLESPACE_PATH="/var/db/postgres4/mgg73"

echo "=== Поиск последнего архива резервной копии ==="
LATEST_BACKUP="$(ls -t "$BACKUP_DIR"/pg111_full_cluster_*.sql.gz | head -n 1)"
echo "Используется архив: $LATEST_BACKUP"

echo "=== Проверка целостности gzip-архива ==="
gzip -t "$LATEST_BACKUP"
echo "Архив корректен"

echo "=== Остановка старого восстановленного экземпляра, если он запущен ==="
if [ -d "$PGDATA" ]; then
    pg_ctl -D "$PGDATA" status >/dev/null 2>&1 && pg_ctl -D "$PGDATA" stop -m fast || true
fi

echo "=== Очистка старых каталогов восстановления ==="
rm -rf "$PGDATA" "$PGWAL"
mkdir -p "$PGWAL" "$TABLESPACE_DIR"
chmod 700 "$PGWAL" "$TABLESPACE_DIR"

echo "=== Инициализация нового кластера PostgreSQL ==="
initdb -D "$PGDATA" \
  -X "$PGWAL" \
  --locale=ru_RU.CP1251 \
  --encoding=WIN1251

echo "=== Настройка postgresql.conf ==="
cat >> "$PGDATA/postgresql.conf" <<'CONFEOF'

# Настройки восстановленного экземпляра для этапа 2
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

echo "=== Настройка pg_hba.conf ==="
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

echo "=== Запуск восстановленного экземпляра PostgreSQL ==="
pg_ctl -D "$PGDATA" start
pg_ctl -D "$PGDATA" status

echo "=== Проверка подключения к служебной базе postgres ==="
psql -p "$PGPORT" -d postgres -c '\conninfo'

echo "=== Проверка пути табличного пространства в архиве ==="
gzip -dc "$LATEST_BACKUP" | grep -n "CREATE TABLESPACE\|$OLD_TABLESPACE_PATH" | head -n 20 || true

echo "=== Восстановление SQL Dump на резервном узле ==="
gzip -dc "$LATEST_BACKUP" \
  | sed "s|$OLD_TABLESPACE_PATH|$NEW_TABLESPACE_PATH|g" \
  | psql -p "$PGPORT" -d postgres -v ON_ERROR_STOP=1

echo "=== Проверка списка баз данных ==="
psql -p "$PGPORT" -d postgres -c '\l'

echo "=== Проверка табличных пространств ==="
psql -p "$PGPORT" -d postgres -c '\db'

echo "=== Проверка подключения к fastorangecity ==="
psql -p "$PGPORT" -d fastorangecity -c '\conninfo'

echo "=== Проверка списка таблиц ==="
psql -p "$PGPORT" -d fastorangecity -c '\dt'

echo "=== Проверка количества строк ==="
psql -p "$PGPORT" -d fastorangecity -c "
SELECT 'clients' AS table_name, count(*) FROM clients
UNION ALL
SELECT 'branches', count(*) FROM branches
UNION ALL
SELECT 'accounts', count(*) FROM accounts
UNION ALL
SELECT 'operations', count(*) FROM operations;
"

echo "=== Проверка размещения таблиц и индексов по табличным пространствам ==="
psql -p "$PGPORT" -d fastorangecity -c "
SELECT
    c.relname AS object_name,
    CASE c.relkind
        WHEN 'r' THEN 'table'
        WHEN 'i' THEN 'index'
        WHEN 'S' THEN 'sequence'
        ELSE c.relkind::text
    END AS object_type,
    COALESCE(t.spcname, 'pg_default') AS tablespace
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'clients',
      'branches',
      'accounts',
      'operations',
      'idx_accounts_client_id',
      'idx_accounts_branch_id',
      'idx_operations_account_id',
      'idx_operations_operation_time'
  )
ORDER BY object_type, object_name;
"

echo "=== Проверка доступа от имени default_user ==="
psql -h localhost -p "$PGPORT" -U default_user -d fastorangecity -c '\conninfo'
psql -h localhost -p "$PGPORT" -U default_user -d fastorangecity -c "SELECT * FROM clients;"
psql -h localhost -p "$PGPORT" -U default_user -d fastorangecity -c "SELECT * FROM operations;"

echo "=== Восстановление на резервном узле завершено успешно ==="
EOF

chmod +x "$HOME/scripts/restore_on_backup_node.sh"
