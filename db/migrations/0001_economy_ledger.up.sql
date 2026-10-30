-- 0001 economy ledger (RP-002, RP-004, RP-005, G-04)
-- Draft skeleton. Server-authoritative, double-entry, idempotent, append-only.
-- Requires 0000. Apply with the mariadb/mysql CLI (uses DELIMITER).
-- Rollback: 0001_economy_ledger.down.sql.
-- owner_ref / actor_ref hold internal pseudonymous references only, never
-- FiveM license, Steam, Discord identifiers or IP addresses.

CREATE TABLE econ_accounts (
  account_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  owner_kind      ENUM('character','business','system') NOT NULL,
  owner_ref       VARCHAR(64)  NOT NULL,
  currency        ENUM('game_cash','game_bank') NOT NULL,
  balance         BIGINT       NOT NULL DEFAULT 0,
  allow_negative  TINYINT(1)   NOT NULL DEFAULT 0,
  status          ENUM('active','frozen') NOT NULL DEFAULT 'active',
  created_at      DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_econ_owner_currency (owner_kind, owner_ref, currency),
  -- Only system accounts (treasury/sink) may go negative; players never.
  CONSTRAINT ck_econ_balance CHECK (allow_negative = 1 OR balance >= 0),
  CONSTRAINT ck_econ_negative_system CHECK (allow_negative = 0 OR owner_kind = 'system')
) ENGINE=InnoDB;

CREATE TABLE econ_transactions (
  tx_id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  idempotency_key  VARCHAR(80)  NOT NULL,
  from_account_id  BIGINT UNSIGNED NOT NULL,
  to_account_id    BIGINT UNSIGNED NOT NULL,
  amount           BIGINT       NOT NULL,
  reason           VARCHAR(64)  NOT NULL,
  actor_ref        VARCHAR(64)  NOT NULL,
  created_at       DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_econ_idempotency (idempotency_key),
  KEY ix_econ_tx_from (from_account_id, created_at),
  KEY ix_econ_tx_to (to_account_id, created_at),
  CONSTRAINT fk_econ_tx_from FOREIGN KEY (from_account_id) REFERENCES econ_accounts (account_id),
  CONSTRAINT fk_econ_tx_to FOREIGN KEY (to_account_id) REFERENCES econ_accounts (account_id),
  CONSTRAINT ck_econ_amount CHECK (amount > 0),
  CONSTRAINT ck_econ_distinct CHECK (from_account_id <> to_account_id)
) ENGINE=InnoDB;

CREATE TABLE econ_ledger_entries (
  entry_id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  tx_id          BIGINT UNSIGNED NOT NULL,
  account_id     BIGINT UNSIGNED NOT NULL,
  delta          BIGINT NOT NULL,
  balance_after  BIGINT NOT NULL,
  KEY ix_econ_entry_account (account_id, entry_id),
  CONSTRAINT fk_econ_entry_tx FOREIGN KEY (tx_id) REFERENCES econ_transactions (tx_id),
  CONSTRAINT fk_econ_entry_account FOREIGN KEY (account_id) REFERENCES econ_accounts (account_id),
  CONSTRAINT ck_econ_delta CHECK (delta <> 0)
) ENGINE=InnoDB;

DELIMITER //

-- Ledger history is append-only. Corrections are new compensating transfers.
CREATE TRIGGER econ_transactions_no_update BEFORE UPDATE ON econ_transactions
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_APPEND_ONLY'//
CREATE TRIGGER econ_transactions_no_delete BEFORE DELETE ON econ_transactions
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_APPEND_ONLY'//
CREATE TRIGGER econ_ledger_no_update BEFORE UPDATE ON econ_ledger_entries
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_APPEND_ONLY'//
CREATE TRIGGER econ_ledger_no_delete BEFORE DELETE ON econ_ledger_entries
FOR EACH ROW SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_APPEND_ONLY'//

-- The only supported way to move money. Returns one row (tx_id, status,
-- currency) where status is 'committed' or 'replayed'. Failures SIGNAL an ECON_* code
-- and roll back everything; callers must never assume a commit on error.
CREATE PROCEDURE econ_transfer(
  IN p_idempotency_key VARCHAR(80),
  IN p_from BIGINT UNSIGNED,
  IN p_to BIGINT UNSIGNED,
  IN p_amount BIGINT,
  IN p_reason VARCHAR(64),
  IN p_actor_ref VARCHAR(64)
)
BEGIN
  DECLARE v_tx_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_prev_from, v_prev_to BIGINT UNSIGNED;
  DECLARE v_prev_amount BIGINT;
  DECLARE v_from_balance, v_to_balance BIGINT;
  DECLARE v_from_neg TINYINT;
  DECLARE v_from_status, v_to_status VARCHAR(16);
  DECLARE v_from_cur, v_to_cur VARCHAR(16);
  DECLARE v_locked INT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_INVALID_AMOUNT';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_SAME_ACCOUNT';
  END IF;
  IF p_idempotency_key IS NULL OR CHAR_LENGTH(p_idempotency_key) < 8 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_INVALID_IDEMPOTENCY_KEY';
  END IF;

  START TRANSACTION;

  -- Lock both accounts in ascending id order to avoid deadlocks between
  -- opposite-direction transfers.
  SELECT COUNT(*) INTO v_locked FROM (
    SELECT account_id FROM econ_accounts
    WHERE account_id IN (p_from, p_to)
    ORDER BY account_id
    FOR UPDATE
  ) AS locked_accounts;
  IF v_locked <> 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_ACCOUNT_NOT_FOUND';
  END IF;

  -- Locking read so a retry sees a concurrently committed duplicate.
  SELECT tx_id, from_account_id, to_account_id, amount
    INTO v_tx_id, v_prev_from, v_prev_to, v_prev_amount
    FROM econ_transactions
    WHERE idempotency_key = p_idempotency_key
    FOR UPDATE;

  IF v_tx_id IS NOT NULL THEN
    IF v_prev_from = p_from AND v_prev_to = p_to AND v_prev_amount = p_amount THEN
      COMMIT;
      SELECT v_tx_id AS tx_id, 'replayed' AS status,
             (SELECT currency FROM econ_accounts WHERE account_id = p_from) AS currency;
    ELSE
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_IDEMPOTENCY_CONFLICT';
    END IF;
  ELSE
    SELECT balance, allow_negative, status, currency
      INTO v_from_balance, v_from_neg, v_from_status, v_from_cur
      FROM econ_accounts WHERE account_id = p_from;
    SELECT balance, status, currency
      INTO v_to_balance, v_to_status, v_to_cur
      FROM econ_accounts WHERE account_id = p_to;

    IF v_from_status <> 'active' OR v_to_status <> 'active' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_ACCOUNT_FROZEN';
    END IF;
    IF v_from_cur <> v_to_cur THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_CURRENCY_MISMATCH';
    END IF;
    IF v_from_neg = 0 AND v_from_balance < p_amount THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_INSUFFICIENT_FUNDS';
    END IF;

    INSERT INTO econ_transactions
      (idempotency_key, from_account_id, to_account_id, amount, reason, actor_ref)
      VALUES (p_idempotency_key, p_from, p_to, p_amount, p_reason, p_actor_ref);
    SET v_tx_id = LAST_INSERT_ID();

    UPDATE econ_accounts SET balance = balance - p_amount WHERE account_id = p_from;
    UPDATE econ_accounts SET balance = balance + p_amount WHERE account_id = p_to;

    INSERT INTO econ_ledger_entries (tx_id, account_id, delta, balance_after)
      VALUES (v_tx_id, p_from, -p_amount, v_from_balance - p_amount),
             (v_tx_id, p_to, p_amount, v_to_balance + p_amount);

    COMMIT;
    SELECT v_tx_id AS tx_id, 'committed' AS status, v_from_cur AS currency;
  END IF;
END//

DELIMITER ;

-- Fixed system accounts: treasury is the only mint source / burn sink.
INSERT INTO econ_accounts (owner_kind, owner_ref, currency, allow_negative)
VALUES ('system', 'treasury', 'game_cash', 1),
       ('system', 'treasury', 'game_bank', 1);

INSERT INTO schema_migrations (version, name) VALUES (1, 'economy_ledger');
