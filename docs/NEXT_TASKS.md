# Next tasks for Codex — draft slices, each via separate PR

1. **Architecture discovery (D-01, D-02):** document asset inventory template and technical-spike decision matrix for Qbox vs legacy/custom; no installation without review.
2. **Contracts (SEC-001/002/014):** propose versioned JSON Schemas for six PRD telemetry events, synthetic fixtures and validation tests; explicitly document privacy and bounded backpressure.
3. **Economy foundation (RP-004, G-04):** design server-authoritative transaction API, ledger schema and negative tests for duplicate submission, concurrent debit and DB outage; do not introduce client-authoritative money.
4. **Admission (NET-005/006/007):** specify connection deferral/queue state machine, CGNAT-safe multi-signal rules, timeout and resilience tests; stay in observe mode first.
5. **Operator workflow (SEC-008/009/013):** propose role-based approval, expiring reversible mitigations and append-only audit before implementation of any action.

For each slice: link PRD IDs, ADR if architecture changes, tests, threat/failure review, privacy notes and rollback. No production deployment or automatic AI enforcement.
