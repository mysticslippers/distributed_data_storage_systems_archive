INSERT INTO clients (surname, name, gender, registered_at) VALUES
('Иванов', 'Иван', 'MALE', '2026-03-01 10:00:00'),
('Петрова', 'Анна', 'FEMALE', '2026-03-02 11:30:00'),
('Сидоров', 'Максим', 'NOT STATED', '2026-03-03 09:15:00');

INSERT INTO branches (branch_name, city, opened_at) VALUES
('Центральный офис', 'Санкт-Петербург', '2020-01-15'),
('Северный филиал', 'Мурманск', '2021-06-10'),
('Южный филиал', 'Сочи', '2022-09-01');

INSERT INTO accounts (client_id, branch_id, balance, opened_at) VALUES
(1, 1, 15000.00, '2026-03-05 12:00:00'),
(2, 2, 22000.50, '2026-03-06 14:20:00'),
(3, 1, 5000.00, '2026-03-07 16:45:00');

INSERT INTO operations (account_id, operation_type, amount, operation_time) VALUES
(1, 'Cash deposit', 5000.00, '2026-03-08 10:00:00'),
(1, 'Cash withdrawal', 1000.00, '2026-03-09 13:00:00'),
(2, 'Credit', 7000.00, '2026-03-10 15:30:00'),
(3, 'Contribution', 2500.00, '2026-03-11 09:40:00');
