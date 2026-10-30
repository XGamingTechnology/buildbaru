-- Synthetic accounts for the sentinel_selftest resource. Staging only.
-- Idempotent: re-running replays the seed transfer instead of minting again.
INSERT IGNORE INTO econ_accounts (owner_kind, owner_ref, currency)
VALUES ('character', 'selftest-a', 'game_cash'),
       ('character', 'selftest-b', 'game_cash');

SET @treasury = (SELECT account_id FROM econ_accounts
                 WHERE owner_kind = 'system' AND owner_ref = 'treasury' AND currency = 'game_cash');
SET @selftest_a = (SELECT account_id FROM econ_accounts
                   WHERE owner_kind = 'character' AND owner_ref = 'selftest-a' AND currency = 'game_cash');

CALL econ_transfer('seed-selftest-a-0001', @treasury, @selftest_a, 1000, 'selftest_seed', 'selftest');
