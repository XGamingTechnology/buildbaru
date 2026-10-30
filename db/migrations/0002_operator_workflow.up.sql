-- 0002 operator workflow (SEC-008, SEC-009, SEC-013, NET-004; provisional IDs)
-- Draft skeleton. Role-based, two-person approved, always-expiring and
-- revocable mitigations, with a hash-chained append-only audit log.
-- Requires 0000. Apply with the mariadb/mysql CLI (uses DELIMITER).
-- Rollback: 0002_operator_workflow.down.sql.
--
-- Operator authentication and MFA happen in the (future) sentinel-api; the
-- database trusts its caller, so only that service account may EXECUTE these
-- procedures. operator_ref is a pseudonymous handle, never a real name/email.
--
-- There is deliberately no permanent ban, IP/ASN block or firewall action
-- kind: action_kind is a closed ENUM and every mitigation has a bounded TTL.

CREATE TABLE ops_operators (
  operator_ref  VARCHAR(64) NOT NULL PRIMARY KEY,
  role          ENUM('viewer','analyst','responder','approver','admin') NOT NULL,
  status        ENUM('active','disabled') NOT NULL DEFAULT 'active',
  mfa_enrolled  TINYINT(1) NOT NULL DEFAULT 0,
  created_at    DATETIME(3) NOT NULL DEFAULT UTC_TIMESTAMP(3)
) ENGINE=InnoDB;

CREATE TABLE ops_mitigations (
  mitigation_id  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  incident_ref   VARCHAR(64) NOT NULL,
  action_kind    ENUM('watchlist','admission_cooldown','temp_rate_limit','resource_disable','player_kick_request') NOT NULL,
  target_ref     VARCHAR(64) NOT NULL,
  reason         VARCHAR(255) NOT NULL,
  evidence_refs  LONGTEXT NOT NULL,
  rollback_ref   VARCHAR(64) NOT NULL,
  requested_by   VARCHAR(64) NOT NULL,
  requested_at   DATETIME(3) NOT NULL,
  expires_at     DATETIME(3) NOT NULL,
  status         ENUM('proposed','active','rejected','revoked','expired') NOT NULL DEFAULT 'proposed',
  decided_by     VARCHAR(64) NULL,
  decided_at     DATETIME(3) NULL,
  KEY ix_ops_status_expiry (status, expires_at),
  KEY ix_ops_target (target_ref, status),
  CONSTRAINT fk_ops_requested_by FOREIGN KEY (requested_by) REFERENCES ops_operators (operator_ref),
  CONSTRAINT ck_ops_evidence CHECK (JSON_VALID(evidence_refs) AND JSON_TYPE(evidence_refs) = 'ARRAY'
                                    AND JSON_LENGTH(evidence_refs) BETWEEN 1 AND 50),
  CONSTRAINT ck_ops_expiry CHECK (expires_at >= requested_at)
) ENGINE=InnoDB;

CREATE TABLE ops_audit_log (
  audit_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  at             DATETIME(3) NOT NULL,
  actor_ref      VARCHAR(64) NOT NULL,
  action         ENUM('proposed','approved','rejected','revoked','expired','operator_changed') NOT NULL,
  mitigation_id  BIGINT UNSIGNED NULL,
  detail         VARCHAR(255) NOT NULL,
  prev_hash      CHAR(64) NOT NULL,
  row_hash       CHAR(64) NOT NULL,
  KEY ix_ops_audit_mitigation (mitigation_id)
) ENGINE=InnoDB;

-- Single-row head of the hash chain; locking it serializes audit appends.
CREATE TABLE ops_audit_head (
  id         TINYINT UNSIGNED NOT NULL PRIMARY KEY,
  last_hash  CHAR(64) NOT NULL,
  CONSTRAINT ck_ops_audit_head_single CHECK (id = 1)
) ENGINE=InnoDB;

INSERT INTO ops_audit_head (id, last_hash) VALUES (1, REPEAT('0', 64));

DELIMITER //

CREATE TRIGGER ops_audit_no_update BEFORE UPDATE ON ops_audit_log
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_APPEND_ONLY'//
CREATE TRIGGER ops_audit_no_delete BEFORE DELETE ON ops_audit_log
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_APPEND_ONLY'//
CREATE TRIGGER ops_mitigations_no_delete BEFORE DELETE ON ops_mitigations
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_APPEND_ONLY'//

-- Guards hold even for direct SQL: evidence and target are immutable, expiry
-- can only move earlier, and status only moves along the allowed edges.
CREATE TRIGGER ops_mitigations_guard BEFORE UPDATE ON ops_mitigations
FOR EACH ROW
BEGIN
  IF NOT (NEW.incident_ref <=> OLD.incident_ref AND NEW.action_kind <=> OLD.action_kind
          AND NEW.target_ref <=> OLD.target_ref AND NEW.reason <=> OLD.reason
          AND NEW.evidence_refs <=> OLD.evidence_refs AND NEW.rollback_ref <=> OLD.rollback_ref
          AND NEW.requested_by <=> OLD.requested_by AND NEW.requested_at <=> OLD.requested_at) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_IMMUTABLE_FIELD';
  END IF;
  IF NEW.expires_at > OLD.expires_at THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_EXPIRY_EXTENSION';
  END IF;
  IF NEW.status <> OLD.status AND NOT (
       (OLD.status = 'proposed' AND NEW.status IN ('active','rejected','revoked','expired'))
    OR (OLD.status = 'active' AND NEW.status IN ('revoked','expired'))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_INVALID_TRANSITION';
  END IF;
END//

-- Internal: append one hash-chained audit row. Caller owns the transaction.
CREATE PROCEDURE ops_audit_append(
  IN p_actor VARCHAR(64), IN p_action VARCHAR(32),
  IN p_mitigation_id BIGINT UNSIGNED, IN p_detail VARCHAR(255)
)
BEGIN
  DECLARE v_prev CHAR(64);
  DECLARE v_at DATETIME(3) DEFAULT UTC_TIMESTAMP(3);
  DECLARE v_hash CHAR(64);
  SELECT last_hash INTO v_prev FROM ops_audit_head WHERE id = 1 FOR UPDATE;
  SET v_hash = SHA2(CONCAT_WS('|', v_prev, DATE_FORMAT(v_at, '%Y-%m-%dT%H:%i:%s.%fZ'),
                              p_actor, p_action, IFNULL(p_mitigation_id, ''), p_detail), 256);
  INSERT INTO ops_audit_log (at, actor_ref, action, mitigation_id, detail, prev_hash, row_hash)
    VALUES (v_at, p_actor, p_action, p_mitigation_id, p_detail, v_prev, v_hash);
  UPDATE ops_audit_head SET last_hash = v_hash WHERE id = 1;
END//

-- Maximum lifetime per action kind, in seconds. NULL = unknown kind.
CREATE PROCEDURE ops_max_ttl(IN p_kind VARCHAR(32), OUT p_max INT)
BEGIN
  SET p_max = CASE p_kind
    WHEN 'player_kick_request' THEN 300
    WHEN 'admission_cooldown' THEN 3600
    WHEN 'temp_rate_limit' THEN 3600
    WHEN 'resource_disable' THEN 86400
    WHEN 'watchlist' THEN 604800
    ELSE NULL END;
END//

-- Returns one row: mitigation_id. Status starts at 'proposed'.
CREATE PROCEDURE ops_propose(
  IN p_operator VARCHAR(64), IN p_kind VARCHAR(32), IN p_target VARCHAR(64),
  IN p_reason VARCHAR(255), IN p_evidence LONGTEXT, IN p_ttl_s INT,
  IN p_incident VARCHAR(64), IN p_rollback VARCHAR(64)
)
BEGIN
  DECLARE v_role VARCHAR(16);
  DECLARE v_max INT;
  DECLARE v_now DATETIME(3) DEFAULT UTC_TIMESTAMP(3);
  DECLARE v_id BIGINT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SELECT role INTO v_role FROM ops_operators WHERE operator_ref = p_operator AND status = 'active';
  IF v_role IS NULL OR v_role NOT IN ('analyst','responder','approver','admin') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_FORBIDDEN';
  END IF;
  CALL ops_max_ttl(p_kind, v_max);
  IF v_max IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_UNKNOWN_ACTION';
  END IF;
  IF p_ttl_s IS NULL OR p_ttl_s <= 0 OR p_ttl_s > v_max THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_INVALID_TTL';
  END IF;
  IF p_evidence IS NULL OR NOT JSON_VALID(p_evidence) OR JSON_TYPE(p_evidence) <> 'ARRAY'
     OR JSON_LENGTH(p_evidence) < 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_EVIDENCE_REQUIRED';
  END IF;
  IF p_rollback IS NULL OR p_rollback = '' OR p_reason IS NULL OR p_reason = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_INVALID_REQUEST';
  END IF;

  START TRANSACTION;
  INSERT INTO ops_mitigations
    (incident_ref, action_kind, target_ref, reason, evidence_refs, rollback_ref,
     requested_by, requested_at, expires_at)
    VALUES (p_incident, p_kind, p_target, p_reason, p_evidence, p_rollback,
            p_operator, v_now, v_now + INTERVAL p_ttl_s SECOND);
  SET v_id = LAST_INSERT_ID();
  CALL ops_audit_append(p_operator, 'proposed', v_id, CONCAT(p_kind, ' ', p_target, ' ttl=', p_ttl_s));
  COMMIT;
  SELECT v_id AS mitigation_id;
END//

-- Shared decision path for approve / reject / revoke.
CREATE PROCEDURE ops_decide(
  IN p_operator VARCHAR(64), IN p_id BIGINT UNSIGNED, IN p_decision VARCHAR(16), IN p_note VARCHAR(255)
)
BEGIN
  DECLARE v_role VARCHAR(16);
  DECLARE v_mfa TINYINT;
  DECLARE v_status VARCHAR(16);
  DECLARE v_requester VARCHAR(64);
  DECLARE v_expires DATETIME(3);
  DECLARE v_now DATETIME(3) DEFAULT UTC_TIMESTAMP(3);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
  SELECT role, mfa_enrolled INTO v_role, v_mfa
    FROM ops_operators WHERE operator_ref = p_operator AND status = 'active';
  SELECT status, requested_by, expires_at INTO v_status, v_requester, v_expires
    FROM ops_mitigations WHERE mitigation_id = p_id FOR UPDATE;
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_NOT_FOUND';
  END IF;
  IF v_role IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_FORBIDDEN';
  END IF;

  IF p_decision IN ('approved', 'rejected') THEN
    IF v_role NOT IN ('approver','admin') OR v_mfa <> 1 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_FORBIDDEN';
    END IF;
    IF v_requester = p_operator THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_TWO_PERSON_RULE';
    END IF;
    IF v_status <> 'proposed' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_INVALID_TRANSITION';
    END IF;
    IF p_decision = 'approved' AND v_expires <= v_now THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_EXPIRED';
    END IF;
    UPDATE ops_mitigations
      SET status = IF(p_decision = 'approved', 'active', 'rejected'), decided_by = p_operator, decided_at = v_now
      WHERE mitigation_id = p_id;
  ELSEIF p_decision = 'revoked' THEN
    -- Rolling back must stay easy: any responder+ or the requester may revoke.
    IF v_role NOT IN ('responder','approver','admin') AND v_requester <> p_operator THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_FORBIDDEN';
    END IF;
    IF v_status NOT IN ('proposed','active') THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_INVALID_TRANSITION';
    END IF;
    UPDATE ops_mitigations
      SET status = 'revoked', decided_by = p_operator, decided_at = v_now,
          expires_at = LEAST(expires_at, v_now)
      WHERE mitigation_id = p_id;
  ELSE
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_INVALID_REQUEST';
  END IF;

  CALL ops_audit_append(p_operator, p_decision, p_id, IFNULL(p_note, ''));
  COMMIT;
  SELECT p_id AS mitigation_id, p_decision AS decision;
END//

CREATE PROCEDURE ops_approve(IN p_operator VARCHAR(64), IN p_id BIGINT UNSIGNED, IN p_note VARCHAR(255))
BEGIN
  CALL ops_decide(p_operator, p_id, 'approved', p_note);
END//

CREATE PROCEDURE ops_reject(IN p_operator VARCHAR(64), IN p_id BIGINT UNSIGNED, IN p_note VARCHAR(255))
BEGIN
  CALL ops_decide(p_operator, p_id, 'rejected', p_note);
END//

CREATE PROCEDURE ops_revoke(IN p_operator VARCHAR(64), IN p_id BIGINT UNSIGNED, IN p_note VARCHAR(255))
BEGIN
  CALL ops_decide(p_operator, p_id, 'revoked', p_note);
END//

-- Marks every proposed/active mitigation past its expiry as expired.
-- Run periodically by the (future) sentinel-policy service. Returns one row: expired count.
CREATE PROCEDURE ops_expire_due()
BEGIN
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_id BIGINT UNSIGNED;
  DECLARE v_count INT DEFAULT 0;
  DECLARE cur CURSOR FOR
    SELECT mitigation_id FROM ops_mitigations
    WHERE status IN ('proposed','active') AND expires_at <= UTC_TIMESTAMP(3)
    ORDER BY mitigation_id FOR UPDATE;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
  OPEN cur;
  expire_loop: LOOP
    FETCH cur INTO v_id;
    IF v_done = 1 THEN
      LEAVE expire_loop;
    END IF;
    UPDATE ops_mitigations SET status = 'expired' WHERE mitigation_id = v_id;
    CALL ops_audit_append('system', 'expired', v_id, '');
    SET v_count = v_count + 1;
  END LOOP;
  CLOSE cur;
  COMMIT;
  SELECT v_count AS expired;
END//

-- Admin-only role management (SEC-013). Admins cannot change their own entry,
-- so nobody can escalate or lock themselves in. The first admin is inserted
-- by a DBA during provisioning, outside this procedure.
CREATE PROCEDURE ops_set_operator(
  IN p_admin VARCHAR(64), IN p_target VARCHAR(64), IN p_role VARCHAR(16),
  IN p_status VARCHAR(16), IN p_mfa TINYINT
)
BEGIN
  DECLARE v_role VARCHAR(16);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SELECT role INTO v_role FROM ops_operators WHERE operator_ref = p_admin AND status = 'active';
  IF v_role IS NULL OR v_role <> 'admin' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_FORBIDDEN';
  END IF;
  IF p_admin = p_target THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OPS_SELF_CHANGE';
  END IF;

  START TRANSACTION;
  INSERT INTO ops_operators (operator_ref, role, status, mfa_enrolled)
    VALUES (p_target, p_role, p_status, p_mfa)
    ON DUPLICATE KEY UPDATE role = VALUES(role), status = VALUES(status), mfa_enrolled = VALUES(mfa_enrolled);
  CALL ops_audit_append(p_admin, 'operator_changed', NULL,
                        CONCAT(p_target, ' role=', p_role, ' status=', p_status, ' mfa=', p_mfa));
  COMMIT;
END//

DELIMITER ;

-- What enforcement points may read: active and not yet past expiry.
CREATE VIEW ops_active_mitigations AS
  SELECT mitigation_id, action_kind, target_ref, expires_at
  FROM ops_mitigations
  WHERE status = 'active' AND expires_at > UTC_TIMESTAMP(3);

INSERT INTO schema_migrations (version, name) VALUES (2, 'operator_workflow');
