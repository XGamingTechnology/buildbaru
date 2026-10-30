"""Unit tests for sentinel_admission pure logic (NET-005/006/007, SEC-004), Lua 5.4
via lupa with synthetic identities. Not evidence of FXServer deferral behaviour."""
import itertools
import unittest

from helpers import SENTINEL, ROOT, lua_runtime, validator_for

ADMISSION = ROOT / 'fivem' / 'resources' / '[sentinel]' / 'sentinel_admission' / 'shared' / 'admission.lua'


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.lua = lua_runtime(ADMISSION)
        self.A = self.lua.globals().SentinelAdmission.Admission
        counter = itertools.count(1000)
        self.random = lambda: next(counter)

    def make(self, **cfg):
        return self.A.new(self.lua.table_from(cfg), self.random)

    def evaluate(self, adm, identity, source='src-shared', now=0):
        fields = {}
        if identity is not None:
            fields['identity'] = identity
        if source is not None:
            fields['source'] = source
        return adm.evaluate(adm, self.lua.table_from(fields), now)

    def test_rejects_unknown_mode(self):
        with self.assertRaises(Exception):
            self.make(mode='ban_everyone')

    def test_observe_mode_never_turns_anyone_away(self):
        adm = self.make(mode='observe', rateMaxAttempts=2)
        missing = self.evaluate(adm, None)
        self.assertEqual((missing.outcome, missing.would, missing.reason), ('accepted', 'rejected', 'missing_identity'))
        for now in range(5):
            d = self.evaluate(adm, 'license:synthetic-a', now=now)
        self.assertEqual((d.outcome, d.would), ('accepted', 'deferred'))

    def test_enforce_rate_limit_is_a_short_cooldown_not_a_ban(self):
        adm = self.make(mode='enforce', rateMaxAttempts=3, rateWindowS=60, cooldownS=30)
        outcomes = [self.evaluate(adm, 'license:synthetic-a', now=t).outcome for t in range(4)]
        self.assertEqual(outcomes, ['accepted', 'accepted', 'accepted', 'deferred'])
        during = self.evaluate(adm, 'license:synthetic-a', now=10)
        self.assertEqual((during.outcome, during.reason), ('deferred', 'cooldown'))
        self.assertEqual(during.retryAfterS, 23)
        after = self.evaluate(adm, 'license:synthetic-a', now=200)
        self.assertEqual((after.outcome, after.reason), ('accepted', 'none'))

    def test_rate_limit_is_per_identity_not_per_ip(self):
        adm = self.make(mode='enforce', rateMaxAttempts=2)
        for t in range(3):
            self.evaluate(adm, 'license:noisy', now=t)
        neighbour = self.evaluate(adm, 'license:neighbour', now=3)
        self.assertEqual(neighbour.outcome, 'accepted')

    def test_cgnat_many_players_one_source_all_admitted(self):
        adm = self.make(mode='enforce', maxPlayers=500)
        for i in range(200):
            d = self.evaluate(adm, f'license:cgnat-{i}', source='src-cgnat', now=i)
            self.assertEqual(d.outcome, 'accepted', i)
            adm.onJoined(adm, i + 1, f'license:cgnat-{i}', 'src-cgnat', i)
        self.assertEqual(d.sharedCount, 199)
        self.assertEqual(self.evaluate(adm, 'license:cgnat-new', source='src-cgnat', now=300).sharedCount, 200)
        adm.onDropped(adm, 1)
        self.assertEqual(adm.sharedCount(adm, d.sourceRef), 199)

    def test_refs_are_random_and_never_contain_raw_values(self):
        adm = self.make()
        d = self.evaluate(adm, 'license:abcdef0123', source='192.0.2.55:30120')
        for ref in (d.identityRef, d.sourceRef):
            self.assertNotIn('abcdef', ref)
            self.assertNotIn('192', ref)
        self.assertEqual(self.evaluate(adm, 'license:abcdef0123', now=1).identityRef, d.identityRef)
        self.assertNotEqual(self.evaluate(adm, 'license:other', now=1).identityRef, d.identityRef)

    def test_queue_is_fifo_and_respects_capacity_and_reservations(self):
        adm = self.make(maxPlayers=2, queueCapacity=3)
        for name in ('a', 'b', 'c'):
            self.assertIsNotNone(adm.enqueue(adm, name, f'p-{name}', 0))
        position, err = adm.enqueue(adm, 'd', 'p-d', 0)
        self.assertIsNone(position)
        self.assertEqual(err, 'queue_full')
        self.assertEqual(adm.tryAdmit(adm, 'b', 0, 1), 'wait')   # not head
        self.assertEqual(adm.tryAdmit(adm, 'a', 0, 1), 'admit')
        self.assertEqual(adm.tryAdmit(adm, 'b', 0, 1), 'admit')  # 0 joined + 1 reserved < 2
        self.assertEqual(adm.tryAdmit(adm, 'c', 0, 1), 'wait')   # 2 slots reserved
        adm.onJoined(adm, 1, None, None, 2)                     # unknown identity: no release
        self.assertEqual(adm.tryAdmit(adm, 'c', 0, 300), 'admit')  # reservations expired

    def test_reconnect_keeps_queue_position(self):
        adm = self.make(maxPlayers=0)
        adm.enqueue(adm, 'tok-1', 'p-a', 0)
        adm.enqueue(adm, 'tok-2', 'p-b', 0)
        self.assertEqual(adm.enqueue(adm, 'tok-9', 'p-a', 5), 1)
        self.assertEqual(adm.position(adm, 'tok-9'), (1, 2))
        self.assertIsNone(adm.position(adm, 'tok-1')[0])

    def test_players_without_identity_do_not_share_a_queue_slot(self):
        adm = self.make(maxPlayers=5)
        self.assertEqual(adm.enqueue(adm, 'x', None, 0), 1)
        self.assertEqual(adm.enqueue(adm, 'y', None, 0), 2)
        self.assertEqual(adm.tryAdmit(adm, 'x', 0, 1), 'admit')
        self.assertEqual(adm.tryAdmit(adm, 'y', 0, 1), 'admit')
        adm.prune(adm, 10)

    def test_queue_timeout_and_leave(self):
        adm = self.make(maxPlayers=0, queueTimeoutS=60)
        adm.enqueue(adm, 'a', 'p-a', 0)
        adm.enqueue(adm, 'b', 'p-b', 0)
        self.assertTrue(adm.leave(adm, 'b'))
        self.assertEqual(adm.tryAdmit(adm, 'a', 0, 30), 'wait')
        self.assertEqual(adm.tryAdmit(adm, 'a', 0, 61), 'timeout')
        self.assertEqual(adm.tryAdmit(adm, 'gone', 0, 61), 'timeout')

    def test_prune_forgets_idle_refs_but_keeps_active_sessions(self):
        adm = self.make(refTtlS=100)
        active = self.evaluate(adm, 'license:active', source='src-a', now=0)
        adm.onJoined(adm, 7, 'license:active', 'src-a', 0)
        idle = self.evaluate(adm, 'license:idle', source='src-b', now=0)
        adm.prune(adm, 1000)
        later = self.evaluate(adm, 'license:active2', source='src-a', now=1000)
        self.assertEqual(later.sourceRef, active.sourceRef)
        self.assertEqual(later.sharedCount, 1)
        self.assertNotEqual(self.evaluate(adm, 'license:idle', now=1001).identityRef, idle.identityRef)

    def test_decision_fits_connection_attempt_schema(self):
        adm = self.make(mode='enforce')
        d = self.evaluate(adm, 'license:synthetic-a')
        event = {
            'schema_version': '1', 'event_type': 'connection_attempt', 'event_id': 'evt-test-1',
            'ts': '2026-10-26T00:00:00Z', 'source_ref_pseudonym': d.identityRef, 'outcome': d.outcome,
            'would_outcome': d.would, 'elapsed_ms': 5, 'edge_reason': d.reason, 'admission_mode': 'enforce',
            'shared_source_count': d.sharedCount, 'queue_position': 1,
        }
        self.assertEqual(list(validator_for('connection_attempt').iter_errors(event)), [])


if __name__ == '__main__':
    unittest.main()
