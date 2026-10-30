"""Integration tests for db/migrations/0001 against a real, disposable MariaDB
(RP-004, G-04). Skipped unless SENTINEL_TEST_DB_* is set. NEVER point these at
a shared or production database: setUp drops and recreates the economy tables.

  SENTINEL_TEST_DB_HOST, SENTINEL_TEST_DB_PORT (3306), SENTINEL_TEST_DB_USER,
  SENTINEL_TEST_DB_PASSWORD, SENTINEL_TEST_DB_NAME
"""
import threading
import unittest

from helpers import DB_ENABLED as ENABLED, MIGRATIONS, connect, run_sql_file


def transfer(conn, key, src, dst, amount, reason='synthetic_test', actor='test-actor'):
    """Returns (status, tx_id, currency) or raises EconError."""
    import pymysql

    with conn.cursor() as cur:
        try:
            cur.execute('CALL econ_transfer(%s, %s, %s, %s, %s, %s)', (key, src, dst, amount, reason, actor))
            row = cur.fetchone()
            while cur.nextset():
                pass
        except pymysql.MySQLError as exc:
            raise EconError(exc.args[1] if len(exc.args) > 1 else str(exc), exc.args[0]) from exc
    return row['status'], row['tx_id'], row['currency']


class EconError(Exception):
    def __init__(self, message, errno):
        super().__init__(message)
        self.message = message
        self.errno = errno


@unittest.skipUnless(ENABLED, 'SENTINEL_TEST_DB_* not set; ledger integration tests skipped')
class LedgerTests(unittest.TestCase):
    def setUp(self):
        run_sql_file(MIGRATIONS / '0000_schema_migrations.up.sql')
        run_sql_file(MIGRATIONS / '0001_economy_ledger.down.sql')
        run_sql_file(MIGRATIONS / '0001_economy_ledger.up.sql')
        self.conn = connect()
        with self.conn.cursor() as cur:
            cur.execute("SELECT account_id FROM econ_accounts WHERE owner_ref='treasury' AND currency='game_cash'")
            self.treasury = cur.fetchone()['account_id']
            ids = []
            for ref, currency in (('char-a', 'game_cash'), ('char-b', 'game_cash'), ('char-c', 'game_bank')):
                cur.execute('INSERT INTO econ_accounts (owner_kind, owner_ref, currency) VALUES (%s, %s, %s)',
                            ('character', ref, currency))
                ids.append(cur.lastrowid)
        self.a, self.b, self.bank = ids

    def tearDown(self):
        self.conn.close()

    def balance(self, account_id):
        with self.conn.cursor() as cur:
            cur.execute('SELECT balance FROM econ_accounts WHERE account_id=%s', (account_id,))
            return cur.fetchone()['balance']

    def count(self, table):
        with self.conn.cursor() as cur:
            cur.execute(f'SELECT COUNT(*) AS n FROM {table}')
            return cur.fetchone()['n']

    def assert_reconciled(self):
        with self.conn.cursor() as cur:
            cur.execute('SELECT COALESCE(SUM(balance), 0) AS total FROM econ_accounts')
            self.assertEqual(cur.fetchone()['total'], 0, 'money created or destroyed')
            cur.execute('''SELECT a.account_id, a.balance, COALESCE(SUM(e.delta), 0) AS ledger
                           FROM econ_accounts a LEFT JOIN econ_ledger_entries e USING (account_id)
                           GROUP BY a.account_id, a.balance HAVING a.balance <> ledger''')
            self.assertEqual(list(cur.fetchall()), [], 'balance differs from ledger')
            cur.execute('SELECT tx_id FROM econ_ledger_entries GROUP BY tx_id HAVING SUM(delta) <> 0 OR COUNT(*) <> 2')
            self.assertEqual(list(cur.fetchall()), [], 'unbalanced double entry')

    def assert_econ_error(self, code, *args):
        with self.assertRaises(EconError) as ctx:
            transfer(self.conn, *args)
        self.assertEqual(ctx.exception.message, code)

    def test_mint_and_transfer(self):
        self.assertEqual(transfer(self.conn, 'mint-a-0001', self.treasury, self.a, 1000)[0], 'committed')
        status, _, currency = transfer(self.conn, 'pay-a-b-0001', self.a, self.b, 250)
        self.assertEqual((status, currency), ('committed', 'game_cash'))
        self.assertEqual((self.balance(self.a), self.balance(self.b)), (750, 250))
        self.assert_reconciled()

    def test_retry_with_same_key_is_replayed_once(self):
        first = transfer(self.conn, 'mint-a-0002', self.treasury, self.a, 500)
        second = transfer(self.conn, 'mint-a-0002', self.treasury, self.a, 500)
        self.assertEqual((first[0], second[0]), ('committed', 'replayed'))
        self.assertEqual(first[1], second[1])
        self.assertEqual(self.balance(self.a), 500)
        self.assertEqual(self.count('econ_transactions'), 1)

    def test_same_key_different_request_conflicts(self):
        transfer(self.conn, 'mint-a-0003', self.treasury, self.a, 500)
        self.assert_econ_error('ECON_IDEMPOTENCY_CONFLICT', 'mint-a-0003', self.treasury, self.a, 900)
        self.assertEqual(self.balance(self.a), 500)

    def test_rejections_leave_no_partial_state(self):
        transfer(self.conn, 'mint-a-0004', self.treasury, self.a, 100)
        before = (self.count('econ_transactions'), self.count('econ_ledger_entries'))
        self.assert_econ_error('ECON_INSUFFICIENT_FUNDS', 'pay-a-b-0004', self.a, self.b, 101)
        self.assert_econ_error('ECON_INVALID_AMOUNT', 'pay-a-b-0005', self.a, self.b, 0)
        self.assert_econ_error('ECON_INVALID_AMOUNT', 'pay-a-b-0006', self.a, self.b, -10)
        self.assert_econ_error('ECON_SAME_ACCOUNT', 'pay-a-a-0007', self.a, self.a, 10)
        self.assert_econ_error('ECON_ACCOUNT_NOT_FOUND', 'pay-a-x-0008', self.a, 999999, 10)
        self.assert_econ_error('ECON_CURRENCY_MISMATCH', 'pay-a-c-0009', self.a, self.bank, 10)
        self.assert_econ_error('ECON_INVALID_IDEMPOTENCY_KEY', 'short', self.a, self.b, 10)
        with self.conn.cursor() as cur:
            cur.execute("UPDATE econ_accounts SET status='frozen' WHERE account_id=%s", (self.b,))
        self.assert_econ_error('ECON_ACCOUNT_FROZEN', 'pay-a-b-0010', self.a, self.b, 10)
        self.assertEqual((self.count('econ_transactions'), self.count('econ_ledger_entries')), before)
        self.assertEqual(self.balance(self.a), 100)
        self.assert_reconciled()

    def test_ledger_is_append_only(self):
        import pymysql

        transfer(self.conn, 'mint-a-0011', self.treasury, self.a, 100)
        for sql in ('UPDATE econ_ledger_entries SET delta = 1', 'DELETE FROM econ_ledger_entries',
                    'UPDATE econ_transactions SET amount = 1', 'DELETE FROM econ_transactions'):
            with self.subTest(sql), self.assertRaises(pymysql.MySQLError) as ctx:
                with self.conn.cursor() as cur:
                    cur.execute(sql)
            self.assertIn('ECON_APPEND_ONLY', str(ctx.exception))

    def test_player_balance_cannot_go_negative_even_by_direct_sql(self):
        import pymysql

        with self.assertRaises(pymysql.MySQLError):
            with self.conn.cursor() as cur:
                cur.execute('UPDATE econ_accounts SET balance = -1 WHERE account_id=%s', (self.a,))

    def run_parallel(self, jobs):
        results, lock = [], threading.Lock()

        def worker(args):
            conn = connect()
            try:
                outcome = transfer(conn, *args)[0]
            except EconError as exc:
                outcome = exc.message
            finally:
                conn.close()
            with lock:
                results.append(outcome)

        threads = [threading.Thread(target=worker, args=(job,)) for job in jobs]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        return results

    def test_concurrent_debits_never_overspend(self):
        transfer(self.conn, 'mint-a-0012', self.treasury, self.a, 1000)
        results = self.run_parallel([(f'spend-a-{i:04d}', self.a, self.b, 100) for i in range(25)])
        self.assertEqual(results.count('committed'), 10)
        self.assertEqual(results.count('ECON_INSUFFICIENT_FUNDS'), 15)
        self.assertEqual((self.balance(self.a), self.balance(self.b)), (0, 1000))
        self.assert_reconciled()

    def test_concurrent_duplicate_submission_commits_once(self):
        results = self.run_parallel([('mint-dup-0013', self.treasury, self.a, 300)] * 12)
        self.assertEqual(results.count('committed'), 1)
        self.assertEqual(results.count('replayed'), 11)
        self.assertEqual(self.balance(self.a), 300)
        self.assertEqual(self.count('econ_transactions'), 1)

    def test_opposite_direction_transfers_do_not_deadlock(self):
        transfer(self.conn, 'mint-a-0014', self.treasury, self.a, 1000)
        transfer(self.conn, 'mint-b-0014', self.treasury, self.b, 1000)
        jobs = []
        for i in range(20):
            jobs.append((f'ab-{i:04d}-xx', self.a, self.b, 10))
            jobs.append((f'ba-{i:04d}-xx', self.b, self.a, 10))
        results = self.run_parallel(jobs)
        self.assertEqual(results, ['committed'] * 40)
        self.assertEqual((self.balance(self.a), self.balance(self.b)), (1000, 1000))
        self.assert_reconciled()

    def test_lock_timeout_fails_without_partial_commit(self):
        transfer(self.conn, 'mint-a-0015', self.treasury, self.a, 100)
        blocker = connect()
        victim = connect()
        try:
            with blocker.cursor() as cur:
                cur.execute('START TRANSACTION')
                cur.execute('SELECT * FROM econ_accounts WHERE account_id=%s FOR UPDATE', (self.a,))
            with victim.cursor() as cur:
                cur.execute('SET SESSION innodb_lock_wait_timeout = 1')
            with self.assertRaises(EconError) as ctx:
                transfer(victim, 'pay-a-b-0015', self.a, self.b, 50)
            self.assertNotIn('ECON_', ctx.exception.message)  # maps to ECON_UNAVAILABLE in Lua
            with blocker.cursor() as cur:
                cur.execute('ROLLBACK')
        finally:
            blocker.close()
            victim.close()
        self.assertEqual(self.balance(self.a), 100)
        # The caller retries with the same key once the database is healthy.
        self.assertEqual(transfer(self.conn, 'pay-a-b-0015', self.a, self.b, 50)[0], 'committed')
        self.assert_reconciled()

    def test_down_migration_removes_schema(self):
        run_sql_file(MIGRATIONS / '0001_economy_ledger.down.sql')
        with self.conn.cursor() as cur:
            cur.execute("SHOW TABLES LIKE 'econ_%%'")
            self.assertEqual(list(cur.fetchall()), [])
        run_sql_file(MIGRATIONS / '0001_economy_ledger.up.sql')


if __name__ == '__main__':
    unittest.main()
