CREATE TABLE clients (
    client_id BIGSERIAL PRIMARY KEY,
    surname VARCHAR(100) NOT NULL,
    name VARCHAR(100) NOT NULL,
    gender VARCHAR(20) NOT NULL CHECK (gender IN ('MALE', 'FEMALE', 'NOT STATED')),
    registered_at TIMESTAMP NOT NULL 
);

CREATE TABLE branches (
    branch_id BIGSERIAL PRIMARY KEY,
    branch_name VARCHAR(150) NOT NULL UNIQUE,
    city VARCHAR(100) NOT NULL,
    opened_at DATE NOT NULL
);

CREATE TABLE accounts (
    account_id BIGSERIAL PRIMARY KEY,
    client_id BIGINT NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    branch_id BIGINT NOT NULL REFERENCES branches(branch_id) ON DELETE RESTRICT,
    balance NUMERIC(12,2) NOT NULL CHECK (balance >= 0),
    opened_at TIMESTAMP NOT NULL
);

CREATE TABLE operations (
    operation_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    operation_type VARCHAR(30) NOT NULL CHECK (
        operation_type IN ('Cash withdrawal', 'Cash deposit', 'Credit', 'Contribution')
    ),
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    operation_time TIMESTAMP NOT NULL
); 
