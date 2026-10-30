"""Integration tests for db/migrations/0002 operator workflow (SEC-008/009/013)
against a disposable MariaDB. Skipped unless SENTINEL_TEST_DB_* is set. setUp
drops and recreates the ops_* tables: never use a shared or production DB."""
import hashlib
import json
import threading
import time
import unittest

from helpers import DB_ENABLED, MIGRATIONS, connect, run_sql_file

GENESIS = '0' * 64
EVIDENCE = json.dumps(['evt-synthetic-1', 'evt-synthetic-2'])


class OpsError(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message


def call(conn, proc, *args):
    import pymysql

    with conn.cursor() as cur:
        try:
            cur.execute(f'CALL {proc}({", ".join(["%s"] * len(args))})', args)
            row = cur.fetchone() if cur.description else None
            while cur.nextset():
                pass
        except pymysql.MySQLError as exc:
            raise OpsError(exc.args[1] if len(exc.args) > 1 else str(exc)) from exc
    return row


@unittest.skipUnless(DB_ENABLED, 'SENTINEL_TEST_DB_* not set; operator workflow tests skipped')
class OperatorWorkflowTests(unittest.TestCase):
    def setUp(self):
        run_sql_file(MIGRATIONS / '0000_schema_migrations.up.sql')
        run_sql_file(MIGRATIONS / '0002_operator_workflow.down.sql')
        run_sql_file(MIGRATIONS / '0002_operator_workflow.up.sql')
        self.conn = connect()
        self.sql('''INSERT INTO ops_operators (operator_ref, role, status, mfa_enrolled) VALUES
            ('op-admin', 'admin', 'active', 1),
            ('op-viewer', 'viewer', 'active', 0),
            ('op-analyst', 'analyst', 'active', 0),
            ('op-responder', 'responder', 'active', 1),
            ('op-approver', 'approver', 'active', 1),
            ('op-approver2', 'approver', 'active', 1),
            ('op-nomfa', 'approver', 'active', 0),
            ('op-gone', 'approver', 'disabled', 1)''')

    def tearDown(self):
        self.conn.close()

    def sql(self, statement, args=None):
        with self.conn.cursor() as cur:
            cur.execute(statement, args)
            return list(cur.fetchall())

    def propose(self, operator='op-analyst', kind='admission_cooldown', ttl=600, evidence=EVIDENCE,
                target='p-synthetic-1', conn=None):
        row = call(conn or self.conn, 'ops_propose', operator, kind, target, 'synthetic reason',
                   evidence, ttl, 'inc-synthetic-1', 'rb-synthetic-1')
        return row['mitigation_id']

    def status(self, mitigation_id):
        return self.sql('SELECT status FROM ops_mitigations WHERE mitigation_id=%s', (mitigation_id,))[0]['status']

    def active_ids(self):
        return [r['mitigation_id'] for r in self.sql('SELECT mitigation_id FROM ops_active_mitigations')]

    def assert_ops_error(self, code, fn, *args, **kwargs):
        with self.assertRaises(OpsError) as ctx:
            fn(*args, **kwargs)
        self.assertIn(code, ctx.exception.message)

    def assert_chain_valid(self):
        rows = self.sql('SELECT * FROM ops_audit_log ORDER BY audit_id')
        prev = GENESIS
        for row in rows:
            self.assertEqual(row['prev_hash'], prev, row['audit_id'])
            payload = '|'.join([
                prev, row['at'].strftime('%Y-%m-%dT%H:%M:%S.%fZ'), row['actor_ref'], row['action'],
                '' if row['mitigation_id'] is None else str(row['mitigation_id']), row['detail'],
            ])
            prev = hashlib.sha256(payload.encode()).hexdigest()
            self.assertEqual(row['row_hash'], prev, row['audit_id'])
        self.assertEqual(self.sql('SELECT last_hash FROM ops_audit_head')[0]['last_hash'], prev)
        return rows

    def test_propose_approve_activates_and_audits(self):
        mid = self.propose()
        self.assertEqual(self.status(mid), 'proposed')
        self.assertEqual(self.active_ids(), [])
        call(self.conn, 'ops_approve', 'op-approver', mid, 'evidence reviewed')
        self.assertEqual(self.status(mid), 'active')
        self.assertEqual(self.active_ids(), [mid])
        rows = self.assert_chain_valid()
        self.assertEqual([(r['action'], r['actor_ref']) for r in rows],
                         [('proposed', 'op-analyst'), ('approved', 'op-approver')])

    def test_role_checks(self):
        self.assert_ops_error('OPS_FORBIDDEN', self.propose, operator='op-viewer')
        self.assert_ops_error('OPS_FORBIDDEN', self.propose, operator='op-gone')
        self.assert_ops_error('OPS_FORBIDDEN', self.propose, operator='op-unknown')
        mid = self.propose()
        self.assert_ops_error('OPS_FORBIDDEN', call, self.conn, 'ops_approve', 'op-analyst', mid, '')
        self.assert_ops_error('OPS_FORBIDDEN', call, self.conn, 'ops_approve', 'op-responder', mid, '')
        self.assert_ops_error('OPS_FORBIDDEN', call, self.conn, 'ops_approve', 'op-nomfa', mid, '')
        self.assert_ops_error('OPS_FORBIDDEN', call, self.conn, 'ops_approve', 'op-gone', mid, '')
        self.assertEqual(self.status(mid), 'proposed')

    def test_two_person_rule(self):
        mid = self.propose(operator='op-approver')
        self.assert_ops_error('OPS_TWO_PERSON_RULE', call, self.conn, 'ops_approve', 'op-approver', mid, '')
        call(self.conn, 'ops_approve', 'op-approver2', mid, '')
        self.assertEqual(self.status(mid), 'active')

    def test_no_ban_or_firewall_actions_exist(self):
        for kind in ('permanent_ban', 'ip_block', 'asn_block', 'firewall_rule'):
            self.assert_ops_error('OPS_UNKNOWN_ACTION', self.propose, kind=kind)
        with self.assertRaises(Exception):
            self.sql('''INSERT INTO ops_mitigations (incident_ref, action_kind, target_ref, reason,
                        evidence_refs, rollback_ref, requested_by, requested_at, expires_at)
                        VALUES ('inc', 'permanent_ban', 't', 'r', '["e"]', 'rb', 'op-analyst',
                                UTC_TIMESTAMP(3), UTC_TIMESTAMP(3) + INTERVAL 1 HOUR)''')

    def test_ttl_is_required_and_bounded_per_kind(self):
        for ttl in (0, -5, None):
            self.assert_ops_error('OPS_INVALID_TTL', self.propose, ttl=ttl)
        self.assert_ops_error('OPS_INVALID_TTL', self.propose, kind='player_kick_request', ttl=301)
        self.assert_ops_error('OPS_INVALID_TTL', self.propose, kind='admission_cooldown', ttl=3601)
        self.assert_ops_error('OPS_INVALID_TTL', self.propose, kind='watchlist', ttl=604801)
        self.propose(kind='resource_disable', ttl=86400)

    def test_evidence_is_required(self):
        for evidence in ('[]', 'null', '{"evt": 1}', 'not json', None):
            self.assert_ops_error('OPS_EVIDENCE_REQUIRED', self.propose, evidence=evidence)
        self.assertEqual(self.sql('SELECT COUNT(*) AS n FROM ops_mitigations')[0]['n'], 0)

    def test_revoke_rules(self):
        own = self.propose()
        call(self.conn, 'ops_revoke', 'op-analyst', own, 'requester withdraws')
        self.assertEqual(self.status(own), 'revoked')

        other = self.propose()
        call(self.conn, 'ops_approve', 'op-approver', other, '')
        self.assert_ops_error('OPS_FORBIDDEN', call, self.conn, 'ops_revoke', 'op-viewer', other, '')
        call(self.conn, 'ops_revoke', 'op-responder', other, 'false positive')
        self.assertEqual(self.status(other), 'revoked')
        self.assertEqual(self.active_ids(), [])
        self.assert_ops_error('OPS_INVALID_TRANSITION', call, self.conn, 'ops_revoke', 'op-responder', other, '')
        self.assert_chain_valid()

    def test_rejected_cannot_be_approved_later(self):
        mid = self.propose()
        call(self.conn, 'ops_reject', 'op-approver', mid, 'insufficient evidence')
        self.assert_ops_error('OPS_INVALID_TRANSITION', call, self.conn, 'ops_approve', 'op-approver2', mid, '')
        self.assertEqual(self.status(mid), 'rejected')

    def test_expiry_is_enforced_and_audited(self):
        mid = self.propose(ttl=1)
        call(self.conn, 'ops_approve', 'op-approver', mid, '')
        stale = self.propose(ttl=1)
        time.sleep(1.3)
        self.assertEqual(self.active_ids(), [])
        self.assert_ops_error('OPS_EXPIRED', call, self.conn, 'ops_approve', 'op-approver', stale, '')
        self.assertEqual(call(self.conn, 'ops_expire_due')['expired'], 2)
        self.assertEqual((self.status(mid), self.status(stale)), ('expired', 'expired'))
        self.assertEqual(call(self.conn, 'ops_expire_due')['expired'], 0)
        rows = self.assert_chain_valid()
        self.assertEqual([r['actor_ref'] for r in rows if r['action'] == 'expired'], ['system', 'system'])

    def test_direct_sql_cannot_bypass_guards(self):
        mid = self.propose()
        call(self.conn, 'ops_approve', 'op-approver', mid, '')
        cases = [
            ('UPDATE ops_mitigations SET expires_at = expires_at + INTERVAL 1 DAY', 'OPS_EXPIRY_EXTENSION'),
            ("UPDATE ops_mitigations SET target_ref = 'p-someone-else'", 'OPS_IMMUTABLE_FIELD'),
            ("UPDATE ops_mitigations SET evidence_refs = '[\"evt-x\"]'", 'OPS_IMMUTABLE_FIELD'),
            ("UPDATE ops_mitigations SET status = 'proposed'", 'OPS_INVALID_TRANSITION'),
            ('DELETE FROM ops_mitigations', 'OPS_APPEND_ONLY'),
            ("UPDATE ops_audit_log SET detail = 'edited'", 'OPS_APPEND_ONLY'),
            ('DELETE FROM ops_audit_log', 'OPS_APPEND_ONLY'),
        ]
        for statement, code in cases:
            with self.subTest(statement):
                self.assert_ops_error(code, self._raw, statement)
        call(self.conn, 'ops_revoke', 'op-responder', mid, '')
        self.assert_ops_error('OPS_INVALID_TRANSITION', self._raw, "UPDATE ops_mitigations SET status = 'active'")
        self.assert_chain_valid()

    def _raw(self, statement):
        import pymysql

        try:
            self.sql(statement)
        except pymysql.MySQLError as exc:
            raise OpsError(exc.args[1] if len(exc.args) > 1 else str(exc)) from exc

    def test_operator_management_is_admin_only_and_audited(self):
        call(self.conn, 'ops_set_operator', 'op-admin', 'op-new', 'responder', 'active', 1)
        self.assertEqual(self.sql("SELECT role FROM ops_operators WHERE operator_ref='op-new'")[0]['role'], 'responder')
        call(self.conn, 'ops_set_operator', 'op-admin', 'op-new', 'viewer', 'disabled', 0)
        self.assert_ops_error('OPS_FORBIDDEN', self.propose, operator='op-new')
        self.assert_ops_error('OPS_SELF_CHANGE', call, self.conn, 'ops_set_operator', 'op-admin', 'op-admin', 'viewer', 'active', 1)
        self.assert_ops_error('OPS_FORBIDDEN', call, self.conn, 'ops_set_operator', 'op-approver', 'op-analyst', 'admin', 'active', 1)
        rows = self.assert_chain_valid()
        self.assertEqual([r['action'] for r in rows], ['operator_changed', 'operator_changed'])

    def test_concurrent_appends_keep_one_linear_chain(self):
        errors = []

        def worker(i):
            conn = connect()
            try:
                self.propose(target=f'p-synthetic-{i}', conn=conn)
            except Exception as exc:  # noqa: BLE001 - surfaced through the assertion below
                errors.append(exc)
            finally:
                conn.close()

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(15)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(errors, [])
        self.assertEqual(len(self.assert_chain_valid()), 15)

    def test_down_migration_removes_schema(self):
        run_sql_file(MIGRATIONS / '0002_operator_workflow.down.sql')
        self.assertEqual(self.sql("SHOW TABLES LIKE 'ops_%%'"), [])
        run_sql_file(MIGRATIONS / '0002_operator_workflow.up.sql')


if __name__ == '__main__':
    unittest.main()
