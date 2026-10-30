-- Rollback for 0003. Accounts that were opened stay; only the procedure goes.
DROP PROCEDURE IF EXISTS econ_open_account;
DELETE FROM schema_migrations WHERE version = 3;
