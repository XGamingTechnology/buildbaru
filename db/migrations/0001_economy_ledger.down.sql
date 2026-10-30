-- Rollback for 0001. DESTROYS all economy data: only for local/staging, or
-- production after a verified backup and approved change (see RUNBOOK.md).
DROP PROCEDURE IF EXISTS econ_transfer;
DROP TRIGGER IF EXISTS econ_ledger_no_delete;
DROP TRIGGER IF EXISTS econ_ledger_no_update;
DROP TRIGGER IF EXISTS econ_transactions_no_delete;
DROP TRIGGER IF EXISTS econ_transactions_no_update;
DROP TABLE IF EXISTS econ_ledger_entries;
DROP TABLE IF EXISTS econ_transactions;
DROP TABLE IF EXISTS econ_accounts;
DELETE FROM schema_migrations WHERE version = 1;
