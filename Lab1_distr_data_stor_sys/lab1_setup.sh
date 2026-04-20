#!/usr/bin/env bash
set -euo pipefail

# --- Переменные окружения ---
export PGDATA="$HOME/ymy46"          # Директория кластера
export PGPORT="9530"                 # Порт PostgreSQL
export PGHOST="localhost"            # Хост для TCP/IP-подключений

WAL_DIR="$HOME/xlg69"                # Директория WAL-файлов
IDX_TBLSPC_DIR="$HOME/mgg73"         # Директория табличного пространства для индексов

DB_NAME="fastorangecity"
DB_USER="default_user"
DB_PASS="default_user_9530"
IDX_TBLSPC_NAME="idxspace"

echo "Подготовка окружения"
mkdir -p "$PGDATA" "$WAL_DIR" "$IDX_TBLSPC_DIR"
ls -ld "$PGDATA" "$WAL_DIR" "$IDX_TBLSPC_DIR"

echo
echo "Проверка русских локалей"
locale -a | grep -i ru || true

echo
echo "Инициализация кластера"
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  initdb -D "$PGDATA" \
    -X "$WAL_DIR" \
    --locale=ru_RU.CP1251 \
    --encoding=WIN1251
else
  echo "Кластер уже инициализирован в $PGDATA, пропускаю initdb"
fi

echo
echo "Настройка postgresql.conf"
cat >> "$PGDATA/postgresql.conf" <<'EOF'

# --- Подключения ---
listen_addresses = 'localhost'               # Принимать TCP/IP-подключения только с localhost
port = 9530                                  # Порт сервера PostgreSQL по заданию

# --- Параметры памяти и производительности ---
max_connections = 30                         # Максимальное количество одновременных подключений
shared_buffers = 2GB                         # Основной буферный кэш PostgreSQL
temp_buffers = 32MB                          # Буферы для временных таблиц в пределах одной сессии
work_mem = 64MB                              # Память на сортировки, хеши и другие операции запроса
checkpoint_timeout = 15min                   # Максимальный интервал между контрольными точками
effective_cache_size = 18GB                  # Оценка доступного кэша ОС и PostgreSQL для планировщика
fsync = on                                   # Синхронизация данных с диском
commit_delay = 10000                         # Задержка коммита 10000 мкс для группировки WAL-записей

# --- Логирование ---
logging_collector = on                       # Включить сбор логов в отдельные файлы
log_destination = 'stderr'                   # Направлять сообщения в stderr
log_directory = 'log'                        # Директория журналов внутри PGDATA
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log' # Имя лог-файла с расширением .log
log_min_messages = notice                    # Минимальный уровень сообщений в журнале: NOTICE
log_connections = on                         # Логировать попытки подключения
log_checkpoints = on                         # Логировать контрольные точки

EOF

echo
echo "Настройка pg_hba.conf"
cat > "$PGDATA/pg_hba.conf" <<'EOF'
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Unix-domain socket
local   all             all                                     peer

# TCP/IP only from localhost
# В отчёте ident не заработал на учебном стенде из-за отсутствия Ident-сервиса,
# поэтому оставляем рабочий вариант через trust только для localhost.
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
EOF

echo
echo "Запуск сервера PostgreSQL"
if pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
  echo "Сервер уже запущен"
else
  pg_ctl -D "$PGDATA" start
fi

echo
echo "Проверка статуса сервера"
pg_ctl -D "$PGDATA" status

echo
echo "Проверка подключений"
echo "--- Через Unix-domain socket ---"
psql -p "$PGPORT" -d postgres -c "SELECT version();"

echo
echo "--- Через TCP/IP localhost ---"
psql -h localhost -p "$PGPORT" -d postgres -c "SELECT current_user, inet_client_addr();"

echo
echo "Создание табличного пространства, роли и базы"
psql -p "$PGPORT" -d postgres <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tablespace WHERE spcname = '${IDX_TBLSPC_NAME}'
    ) THEN
        EXECUTE 'CREATE TABLESPACE ${IDX_TBLSPC_NAME} LOCATION ''${IDX_TBLSPC_DIR}''';
    END IF;
END
\$\$;

DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}'
    ) THEN
        EXECUTE 'CREATE ROLE ${DB_USER} LOGIN PASSWORD ''${DB_PASS}''';
    END IF;
END
\$\$;
EOF

# CREATE DATABASE нельзя выполнить внутри DO, поэтому проверяем отдельно
if ! psql -p "$PGPORT" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  psql -p "$PGPORT" -d postgres <<EOF
CREATE DATABASE ${DB_NAME}
WITH
    TEMPLATE template0
    OWNER ${DB_USER}
    ENCODING 'WIN1251';
EOF
else
  echo "База ${DB_NAME} уже существует"
fi

psql -p "$PGPORT" -d postgres <<EOF
GRANT CREATE ON TABLESPACE ${IDX_TBLSPC_NAME} TO ${DB_USER};
GRANT CONNECT ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

echo
echo "Создание таблиц и наполнение базы данными от имени ${DB_USER}"
psql -h localhost -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" <<'EOF'
CREATE TABLE IF NOT EXISTS clients (
    client_id BIGSERIAL PRIMARY KEY,
    surname VARCHAR(100) NOT NULL,
    name VARCHAR(100) NOT NULL,
    gender VARCHAR(20) NOT NULL CHECK (gender IN ('MALE', 'FEMALE', 'NOT STATED')),
    registered_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS branches (
    branch_id BIGSERIAL PRIMARY KEY,
    branch_name VARCHAR(150) NOT NULL UNIQUE,
    city VARCHAR(100) NOT NULL,
    opened_at DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
    account_id BIGSERIAL PRIMARY KEY,
    client_id BIGINT NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    branch_id BIGINT NOT NULL REFERENCES branches(branch_id) ON DELETE RESTRICT,
    balance NUMERIC(12,2) NOT NULL CHECK (balance >= 0),
    opened_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS operations (
    operation_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    operation_type VARCHAR(30) NOT NULL CHECK (
        operation_type IN ('Cash withdrawal', 'Cash deposit', 'Credit', 'Contribution')
    ),
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    operation_time TIMESTAMP NOT NULL
);

-- Тестовые данные
INSERT INTO clients (surname, name, gender, registered_at) VALUES
('Иванов', 'Иван', 'MALE', '2026-03-01 10:00:00'),
('Петрова', 'Анна', 'FEMALE', '2026-03-02 11:30:00'),
('Сидоров', 'Максим', 'NOT STATED', '2026-03-03 09:15:00')
ON CONFLICT DO NOTHING;

INSERT INTO branches (branch_name, city, opened_at) VALUES
('Центральный офис', 'Санкт-Петербург', '2020-01-15'),
('Северный филиал', 'Мурманск', '2021-06-10'),
('Южный филиал', 'Сочи', '2022-09-01')
ON CONFLICT (branch_name) DO NOTHING;

-- Чтобы не плодить дубликаты, вставляем счета только если таблица пуста
INSERT INTO accounts (client_id, branch_id, balance, opened_at)
SELECT * FROM (VALUES
    (1, 1, 15000.00, '2026-03-05 12:00:00'::timestamp),
    (2, 2, 22000.50, '2026-03-06 14:20:00'::timestamp),
    (3, 1, 5000.00, '2026-03-07 16:45:00'::timestamp)
) AS v(client_id, branch_id, balance, opened_at)
WHERE NOT EXISTS (SELECT 1 FROM accounts);

INSERT INTO operations (account_id, operation_type, amount, operation_time)
SELECT * FROM (VALUES
    (1, 'Cash deposit', 5000.00, '2026-03-08 10:00:00'::timestamp),
    (1, 'Cash withdrawal', 1000.00, '2026-03-09 13:00:00'::timestamp),
    (2, 'Credit', 7000.00, '2026-03-10 15:30:00'::timestamp),
    (3, 'Contribution', 2500.00, '2026-03-11 09:40:00'::timestamp)
) AS v(account_id, operation_type, amount, operation_time)
WHERE NOT EXISTS (SELECT 1 FROM operations);

-- Индексы в отдельном табличном пространстве
CREATE INDEX IF NOT EXISTS idx_accounts_client_id
    ON accounts(client_id)
    TABLESPACE idxspace;

CREATE INDEX IF NOT EXISTS idx_accounts_branch_id
    ON accounts(branch_id)
    TABLESPACE idxspace;

CREATE INDEX IF NOT EXISTS idx_operations_account_id
    ON operations(account_id)
    TABLESPACE idxspace;

CREATE INDEX IF NOT EXISTS idx_operations_operation_time
    ON operations(operation_time)
    TABLESPACE idxspace;
EOF

echo
echo "Список таблиц"
psql -h localhost -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c '\dt'

echo
echo "Список табличных пространств"
psql -h localhost -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c '\db'

echo
echo "Физические пути табличных пространств"
psql -h localhost -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" <<'EOF'
SELECT spcname, pg_tablespace_location(oid)
FROM pg_tablespace
ORDER BY spcname;
EOF
