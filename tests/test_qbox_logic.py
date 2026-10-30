"""Unit tests for the pure logic of rp_qbx_bridge and rp_banking (Lua 5.4 via
lupa). They do not exercise qbx_core, ox_lib or FXServer natives."""
import unittest

from helpers import ROOT, lua_runtime, lua_to_py, pair

RP = ROOT / 'fivem' / 'resources' / '[rp]'


class BridgeLogicTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua_runtime(RP / 'rp_qbx_bridge' / 'shared' / 'logic.lua')
        self.L = self.lua.globals().RpQbxBridge.Logic

    def guard(self, payload, syncing, mode):
        table = self.lua.table_from(payload) if payload is not None else None
        return pair(self.L.guard(table, syncing, mode))

    def test_enforce_blocks_direct_changes_to_ledger_money(self):
        for money_type in ('cash', 'bank'):
            self.assertEqual(self.guard({'source': 1, 'moneyType': money_type, 'amount': 5}, False, 'enforce'),
                             (False, 'economy_anomaly'))

    def test_observe_allows_but_reports(self):
        self.assertEqual(self.guard({'source': 1, 'moneyType': 'bank', 'amount': 5}, False, 'observe'),
                         (True, 'economy_anomaly'))

    def test_own_sync_and_unowned_types_pass(self):
        self.assertEqual(self.guard({'source': 1, 'moneyType': 'bank', 'amount': 5}, True, 'enforce'), (True, None))
        self.assertEqual(self.guard({'source': 1, 'moneyType': 'crypto', 'amount': 5}, False, 'enforce'), (True, None))
        self.assertEqual(self.guard(None, False, 'enforce'), (True, None))

    def test_keys_keep_citizenid_case_and_fit_ledger_rules(self):
        a = self.L.openingKey('AB12cd34', 'bank')
        b = self.L.openingKey('ab12CD34', 'bank')
        self.assertNotEqual(a, b)
        self.assertEqual(a, 'open-AB12cd34-bank')
        self.assertEqual(self.L.paycheckKey('AB12cd34', 1200, 600), 'pay-AB12cd34-2')
        self.assertEqual(self.L.paycheckKey('AB12cd34', 1799, 600), 'pay-AB12cd34-2')
        self.assertEqual(self.L.paycheckKey('AB12cd34', 1800, 600), 'pay-AB12cd34-3')

    def test_actor_label_is_lowercase_without_colon(self):
        self.assertEqual(self.L.actorFor('AB12cd34'), 'cid-ab12cd34')

    def test_citizenid_validation(self):
        self.assertTrue(self.L.validCitizenId('AB12CD34'))
        for bad in ('', 'license:abc', 'a b', None, 12, 'x' * 65):
            self.assertFalse(self.L.validCitizenId(bad), bad)

    def test_first_row_shapes(self):
        row = {'account_id': 9, 'created': 1}
        self.assertEqual(self.L.firstRow(self.lua.table_from([row], recursive=True)).account_id, 9)
        nested = self.lua.table_from([[row], {'affectedRows': 0}], recursive=True)
        self.assertEqual(self.L.firstRow(nested).account_id, 9)
        self.assertIsNone(self.L.firstRow(None))


class BankingLogicTests(unittest.TestCase):
    def setUp(self):
        base = RP / 'rp_banking' / 'shared'
        self.lua = lua_runtime(base / 'config.lua', base / 'logic.lua')
        g = self.lua.globals().RpBanking
        self.L, self.C = g.Logic, g.Config
        self.limits = self.lua.table_from({'maxAmount': 1000})

    def validate(self, kind, req):
        out, code = pair(self.L.validate(kind, self.lua.table_from(req), self.limits))
        return (lua_to_py(out) if out is not None else None), code

    def test_routes(self):
        self.assertEqual(self.L.route('deposit'), ('cash', 'bank'))
        self.assertEqual(self.L.route('withdraw'), ('bank', 'cash'))
        self.assertEqual(self.L.route('transfer'), ('bank', 'bank'))
        self.assertIsNone(self.L.route('loan'))

    def test_valid_requests_are_normalized(self):
        out, code = self.validate('deposit', {'amount': 100.0, 'requestId': 'abcdef12'})
        self.assertIsNone(code)
        self.assertEqual(out, {'amount': 100, 'requestId': 'abcdef12'})
        out, _ = self.validate('transfer', {'amount': 5, 'requestId': 'abcdef12', 'targetId': 7.0})
        self.assertEqual(out['targetId'], 7)

    def test_rejections(self):
        cases = [
            ('loan', {'amount': 5, 'requestId': 'abcdef12'}, 'BANK_INVALID_REQUEST'),
            ('deposit', {'amount': 0, 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': -5, 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': 1.5, 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': 1001, 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': '100', 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': float('inf'), 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': float('nan'), 'requestId': 'abcdef12'}, 'BANK_INVALID_AMOUNT'),
            ('deposit', {'amount': 5, 'requestId': 'short'}, 'BANK_INVALID_REQUEST'),
            ('deposit', {'amount': 5, 'requestId': 'has space 123'}, 'BANK_INVALID_REQUEST'),
            ('deposit', {'amount': 5, 'requestId': 'a' * 41}, 'BANK_INVALID_REQUEST'),
            ('transfer', {'amount': 5, 'requestId': 'abcdef12'}, 'BANK_INVALID_TARGET'),
            ('transfer', {'amount': 5, 'requestId': 'abcdef12', 'targetId': 0}, 'BANK_INVALID_TARGET'),
            ('transfer', {'amount': 5, 'requestId': 'abcdef12', 'targetId': 2.5}, 'BANK_INVALID_TARGET'),
        ]
        for kind, req, code in cases:
            with self.subTest(kind=kind, req=req):
                self.assertEqual(self.validate(kind, req), (None, code))

    def test_idempotency_key(self):
        self.assertEqual(self.L.keyFor('AB12cd34', 'deposit', 'abcdef12'), 'bank-AB12cd34-deposit-abcdef12')
        self.assertNotEqual(self.L.keyFor('AB12cd34', 'deposit', 'abcdef12'),
                            self.L.keyFor('AB12cd34', 'withdraw', 'abcdef12'))
        self.assertIsNone(self.L.keyFor('C' * 64, 'transfer', 'a' * 40))

    def test_location_check(self):
        first = self.C.locations[1]
        near = self.lua.table_from({'x': first.x + 1, 'y': first.y + 1, 'z': first.z})
        far = self.lua.table_from({'x': 0, 'y': 0, 'z': 0})
        self.assertTrue(self.L.isNear(near, self.C.locations, self.C.radius))
        self.assertFalse(self.L.isNear(far, self.C.locations, self.C.radius))
        self.assertFalse(self.L.isNear(None, self.C.locations, self.C.radius))

    def test_rate_limiter_is_per_character_and_slides(self):
        rl = self.L.RateLimiter.new(3, 10)
        self.assertEqual([rl.allow(rl, 'A', t) for t in (0, 1, 2, 3)], [True, True, True, False])
        self.assertTrue(rl.allow(rl, 'B', 3))
        self.assertTrue(rl.allow(rl, 'A', 10))
        rl.prune(rl, 100)
        self.assertEqual(len(dict(rl.hits.items())), 0)


if __name__ == '__main__':
    unittest.main()
