"""Contract tests for the six v1 telemetry schemas (SEC-001/002/014)."""
import unittest

from helpers import ROOT, SCHEMAS, load_json, validator_for

EVENT_TYPES = [
    'connection_attempt', 'game_session', 'economic_mutation',
    'game_abuse_signal', 'network_interval', 'security_incident',
]


class ContractTests(unittest.TestCase):
    def test_exactly_six_schemas(self):
        names = sorted(p.name.removesuffix('.schema.json') for p in SCHEMAS.glob('*.schema.json'))
        self.assertEqual(names, sorted(EVENT_TYPES))

    def test_schemas_are_closed(self):
        for event_type in EVENT_TYPES:
            schema = load_json(SCHEMAS / f'{event_type}.schema.json')
            self.assertIs(schema['additionalProperties'], False, event_type)

    def test_examples_are_valid(self):
        events = load_json(ROOT / 'contracts' / 'event-examples.json')['events']
        self.assertEqual(sorted({e['event_type'] for e in events}), sorted(EVENT_TYPES))
        for event in events:
            errors = list(validator_for(event['event_type']).iter_errors(event))
            self.assertEqual(errors, [], event['event_id'])

    def test_invalid_fixtures_are_rejected(self):
        cases = load_json(ROOT / 'contracts' / 'fixtures' / 'invalid' / 'cases.json')['cases']
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            event = case['event']
            with self.subTest(case['reason']):
                self.assertFalse(validator_for(event['event_type']).is_valid(event))


if __name__ == '__main__':
    unittest.main()
