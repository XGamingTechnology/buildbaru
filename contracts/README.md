# Event contracts (draft v1)

Canonical telemetry events from PRD §13.2, as closed JSON Schemas (2020-12) in
`schemas/v1/`: `connection_attempt`, `game_session`, `economic_mutation`,
`game_abuse_signal`, `network_interval`, `security_incident`.

- `additionalProperties: false` everywhere, so identifiers or addresses cannot
  be added to an event without a reviewed schema change.
- Timestamps are UTC (`Z`). Money deltas are non-zero integers.
- Incident decisions require an approver, expiry and rollback reference.
- `event-examples.json` holds valid synthetic events and
  `fixtures/invalid/cases.json` holds negative cases. Both are checked by
  `tests/test_contracts.py`.

Still open: transport, retention (D-08), ownership, and reconciliation of the
fields with the full PRD. Breaking changes require a new `v2` directory.
