-- 0003 idempotent account opening for the game (RP-004, G-04; provisional IDs).
-- Requires 0001. The game's DB user only has SELECT and EXECUTE, so opening an
-- account goes through this procedure instead of a direct INSERT.
-- Rollback: 0003_econ_open_account.down.sql.

DELIMITER //

-- Returns one row: (account_id, created) where created is 1 for a new account.
-- Only character and business accounts can be opened here; system accounts and
-- allow_negative stay under migration control.
CREATE PROCEDURE econ_open_account(
  IN p_owner_kind VARCHAR(16),
  IN p_owner_ref VARCHAR(64),
  IN p_currency VARCHAR(16)
)
BEGIN
  DECLARE v_id BIGINT UNSIGNED DEFAULT NULL;
  DECLARE v_created TINYINT DEFAULT 0;

  IF p_owner_kind NOT IN ('character', 'business') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_INVALID_REQUEST';
  END IF;
  IF p_owner_ref IS NULL OR p_owner_ref NOT REGEXP '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_INVALID_REQUEST';
  END IF;
  IF p_currency NOT IN ('game_cash', 'game_bank') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ECON_INVALID_REQUEST';
  END IF;

  INSERT IGNORE INTO econ_accounts (owner_kind, owner_ref, currency)
    VALUES (p_owner_kind, p_owner_ref, p_currency);
  IF ROW_COUNT() = 1 THEN
    SET v_created = 1;
  END IF;

  SELECT account_id INTO v_id FROM econ_accounts
    WHERE owner_kind = p_owner_kind AND owner_ref = p_owner_ref AND currency = p_currency;
  SELECT v_id AS account_id, v_created AS created;
END//

DELIMITER ;

INSERT INTO schema_migrations (version, name) VALUES (3, 'econ_open_account');
