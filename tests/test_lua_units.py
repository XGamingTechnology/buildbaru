"""Unit tests for pure Lua modules, run on Lua 5.4 via lupa.
These do NOT prove behaviour inside FXServer (natives, oxmysql, exports)."""
import unittest

from helpers import ECONOMY, SENTINEL, lua_runtime, lua_to_py, pair, validator_for

TS = '2026-10-26T00:00:00Z'


class QueueTests(unittest.TestCase):
    def setUp(self):
        lua = lua_runtime(SENTINEL / 'shared' / 'queue.lua')
        self.Queue = lua.globals().SentinelTelemetry.Queue

    def test_fifo_and_wraparound(self):
        q = self.Queue.new(3)
        for i in (1, 2, 3):
            self.assertTrue(q.push(q, i))
        self.assertEqual(list(q.drain(q, 2).values()), [1, 2])
        self.assertTrue(q.push(q, 4))
        self.assertTrue(q.push(q, 5))
        self.assertEqual(list(q.drain(q).values()), [3, 4, 5])
        self.assertEqual(q.stats(q).queued, 0)

    def test_overflow_is_bounded_and_counted(self):
        q = self.Queue.new(100)
        accepted = sum(1 for i in range(1000) if q.push(q, i))
        stats = q.stats(q)
        self.assertEqual(accepted, 100)
        self.assertEqual(stats.queued, 100)
        self.assertEqual(stats.dropped, 900)

    def test_rejects_invalid_capacity(self):
        for bad in (0, -1, 1.5):
            with self.assertRaises(Exception):
                self.Queue.new(bad)


class EnvelopeTests(unittest.TestCase):
    def setUp(self):
        lua = lua_runtime(SENTINEL / 'shared' / 'envelope.lua')
        self.lua = lua
        self.Envelope = lua.globals().SentinelTelemetry.Envelope

    def build(self, event_type, fields):
        env, err = pair(self.Envelope.build(event_type, self.lua.table_from(fields, recursive=True), TS, 'evt-test-1'))
        return (lua_to_py(env) if env is not None else None), err

    def test_lua_envelopes_match_v1_schema(self):
        samples = {
            'game_session': {'session_ref': 'sess-1', 'phase': 'dropped', 'duration_s': 10, 'drop_category': 'quit'},
            'economic_mutation': {
                'tx_id': 'tx-1', 'account_ref': 'acct-3', 'counterparty_ref': 'acct-4', 'delta': -100,
                'currency': 'game_cash', 'cause': 'shop_purchase', 'idempotency_key': 'shop-0001-abc',
                'actor_ref': 'char-3', 'status': 'committed'},
            'network_interval': {'source': 'fxserver', 'interval_s': 60,
                                 'metrics': {'players': 4, 'telemetry_dropped': 0, 'telemetry_queued': 2}},
        }
        for event_type, fields in samples.items():
            env, err = self.build(event_type, fields)
            self.assertIsNone(err, event_type)
            errors = list(validator_for(event_type).iter_errors(env))
            self.assertEqual(errors, [], event_type)

    def test_rejects_unknown_event_type(self):
        env, err = self.build('player_chat', {})
        self.assertIsNone(env)
        self.assertEqual(err, 'unknown_event_type')

    def test_rejects_identifiers_and_addresses(self):
        bad = [
            {'ip': 'x'},
            {'player_ip': 'x'},
            {'license': 'x'},
            {'note': 'license:synthetic'},
            {'note': 'steam:110000100000000'},
            {'nested': {'deeper': '192.0.2.10'}},
            {'metrics': {'Discord': 'x'}},
        ]
        for fields in bad:
            with self.subTest(fields):
                env, err = self.build('game_session', fields)
                self.assertIsNone(env)
                self.assertTrue(err.startswith('forbidden_field'), err)

    def test_drop_reason_is_categorised_not_forwarded(self):
        cases = {
            'Server->client connection timed out.': 'timeout',
            'Game crashed: synthetic': 'crash',
            'Kicked by admin': 'kicked',
            'Exiting': 'quit',
            'Disconnected.': 'quit',
            'something else': 'unknown',
            None: 'unknown',
        }
        for reason, expected in cases.items():
            self.assertEqual(self.Envelope.classifyDrop(reason), expected, reason)


class EconomyValidateTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua_runtime(ECONOMY / 'shared' / 'validate.lua')
        self.V = self.lua.globals().RpEconomy.Validate
        self.limits = self.lua.table_from({'maxAmount': 1000})

    def req(self, **overrides):
        base = {'from': 3, 'to': 4, 'amount': 100, 'reason': 'shop_purchase',
                'actor': 'char-3', 'idempotencyKey': 'shop-0001-abc'}
        base.update(overrides)
        return self.lua.table_from({k: v for k, v in base.items() if v is not None})

    def check(self, **overrides):
        return pair(self.V.transfer(self.req(**overrides), self.limits))

    def test_valid_request(self):
        self.assertEqual(self.check(), (True, None))

    def test_rejections(self):
        cases = [
            ({'amount': 0}, 'ECON_INVALID_AMOUNT'),
            ({'amount': -5}, 'ECON_INVALID_AMOUNT'),
            ({'amount': 1.5}, 'ECON_INVALID_AMOUNT'),
            ({'amount': 100.0}, 'ECON_INVALID_AMOUNT'),
            ({'amount': 1001}, 'ECON_INVALID_AMOUNT'),
            ({'amount': '100'}, 'ECON_INVALID_AMOUNT'),
            ({'to': 3}, 'ECON_SAME_ACCOUNT'),
            ({'from': None}, 'ECON_INVALID_REQUEST'),
            ({'idempotencyKey': 'short'}, 'ECON_INVALID_IDEMPOTENCY_KEY'),
            ({'idempotencyKey': 'has space 123'}, 'ECON_INVALID_IDEMPOTENCY_KEY'),
            ({'idempotencyKey': 'k' * 81}, 'ECON_INVALID_IDEMPOTENCY_KEY'),
            ({'reason': 'DROP TABLE'}, 'ECON_INVALID_REQUEST'),
            ({'actor': 'license:abc'}, 'ECON_INVALID_REQUEST'),
        ]
        for overrides, code in cases:
            with self.subTest(overrides):
                self.assertEqual(self.check(**overrides), (False, code))

    def test_db_error_mapping_fails_closed(self):
        self.assertEqual(self.V.mapDbError('ER_SIGNAL_EXCEPTION: ECON_INSUFFICIENT_FUNDS'), 'ECON_INSUFFICIENT_FUNDS')
        self.assertEqual(self.V.mapDbError('ECON_MADE_UP_CODE'), 'ECON_UNAVAILABLE')
        self.assertEqual(self.V.mapDbError('connect ETIMEDOUT'), 'ECON_UNAVAILABLE')

    def test_extract_call_row_shapes(self):
        row = {'tx_id': 7, 'status': 'committed', 'currency': 'game_cash'}
        flat = self.lua.table_from([row], recursive=True)
        nested = self.lua.table_from([[row], {'affectedRows': 0}], recursive=True)
        self.assertEqual(self.V.extractCallRow(flat).tx_id, 7)
        self.assertEqual(self.V.extractCallRow(nested).tx_id, 7)
        for bad in ([], [{'affectedRows': 1}], [{'tx_id': 1, 'status': 'weird'}]):
            self.assertIsNone(self.V.extractCallRow(self.lua.table_from(bad, recursive=True)))
        self.assertIsNone(self.V.extractCallRow(None))


if __name__ == '__main__':
    unittest.main()
