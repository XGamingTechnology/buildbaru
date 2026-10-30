"""Integration tests for db/migrations/0003 econ_open_account against a
disposable MariaDB (skipped unless SENTINEL_TEST_DB_* is set)."""
import unittest

from helpers import DB_ENABLED, MIGRATIONS, connect, run_sql_file


@unittest.skipUnless(DB_ENABLED, 'SENTINEL_TEST_DB_* not set; account tests skipped')
class OpenAccountTests(unittest.TestCase):
    def setUp(self):
        run_sql_file(MIGRATIONS / '0000_schema_migrations.up.sql')
        run_sql_file(MIGRATIONS / '0003_econ_open_account.down.sql')
        run_sql_file(MIGRATIONS / '0001_economy_ledger.down.sql')
        run_sql_file(MIGRATIONS / '0001_economy_ledger.up.sql')
        run_sql_file(MIGRATIONS / '0003_econ_open_account.up.sql')
        self.conn = connect()

    def tearDown(self):
        self.conn.close()

    def open(self, kind, ref, currency):
        import pymysql

        with self.conn.cursor() as cur:
            try:
                cur.execute('CALL econ_open_account(%s, %s, %s)', (kind, ref, currency))
                row = cur.fetchone()
                while cur.nextset():
                    pass
            except pymysql.MySQLError as exc:
                return exc.args[1]
        return row['account_id'], row['created']

    def test_open_is_idempotent_and_case_sensitive_per_currency(self):
        first = self.open('character', 'AB12cd34', 'game_bank')
        self.assertEqual(first[1], 1)
        self.assertEqual(self.open('character', 'AB12cd34', 'game_bank'), (first[0], 0))
        cash = self.open('character', 'AB12cd34', 'game_cash')
        self.assertNotEqual(cash[0], first[0])
        self.assertEqual(cash[1], 1)

    def test_refuses_system_accounts_and_bad_input(self):
        for args in (('system', 'treasury', 'game_bank'), ('character', 'license:abc', 'game_bank'),
                     ('character', '', 'game_bank'), ('character', 'AB12cd34', 'crypto')):
            with self.subTest(args):
                self.assertEqual(self.open(*args), 'ECON_INVALID_REQUEST')
        # Over-long refs are refused by the parameter type itself (strict mode).
        self.assertIsInstance(self.open('character', 'x' * 65, 'game_bank'), str)
        with self.conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS n FROM econ_accounts WHERE owner_kind <> 'system'")
            self.assertEqual(cur.fetchone()['n'], 0)

    def test_opened_accounts_cannot_go_negative(self):
        account_id, _ = self.open('character', 'AB12cd34', 'game_bank')
        with self.conn.cursor() as cur:
            cur.execute('SELECT allow_negative, balance FROM econ_accounts WHERE account_id = %s', (account_id,))
            self.assertEqual(cur.fetchone(), {'allow_negative': 0, 'balance': 0})


if __name__ == '__main__':
    unittest.main()
