-- Rollback for 0002. DESTROYS the operator audit trail: export and archive
-- ops_audit_log first; only for local/staging or an approved production change.
DROP VIEW IF EXISTS ops_active_mitigations;
DROP PROCEDURE IF EXISTS ops_set_operator;
DROP PROCEDURE IF EXISTS ops_expire_due;
DROP PROCEDURE IF EXISTS ops_revoke;
DROP PROCEDURE IF EXISTS ops_reject;
DROP PROCEDURE IF EXISTS ops_approve;
DROP PROCEDURE IF EXISTS ops_decide;
DROP PROCEDURE IF EXISTS ops_propose;
DROP PROCEDURE IF EXISTS ops_max_ttl;
DROP PROCEDURE IF EXISTS ops_audit_append;
DROP TRIGGER IF EXISTS ops_mitigations_guard;
DROP TRIGGER IF EXISTS ops_mitigations_no_delete;
DROP TRIGGER IF EXISTS ops_audit_no_delete;
DROP TRIGGER IF EXISTS ops_audit_no_update;
DROP TABLE IF EXISTS ops_audit_head;
DROP TABLE IF EXISTS ops_audit_log;
DROP TABLE IF EXISTS ops_mitigations;
DROP TABLE IF EXISTS ops_operators;
DELETE FROM schema_migrations WHERE version = 2;
