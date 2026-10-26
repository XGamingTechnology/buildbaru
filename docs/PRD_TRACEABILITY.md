# PRD traceability — first implementation slices

| Slice | PRD IDs | Acceptance evidence expected |
|---|---|---|
| Protected edge | NET-001, NET-002, NET-003, NET-008 | Vendor PoC, no origin bypass, measured traffic path |
| Restricted operations | NET-004, SEC-013, NFR-14 | Private admin/DB/Redis, audited operator access |
| Fail-safe join | NET-005, NET-006, NET-007, SEC-004 | Queue tests, CGNAT tests, safe failure mode |
| Economy integrity | RP-002, RP-004, RP-005, G-04 | Atomic ledger, idempotent replay, race/restore tests |
| Telemetry | SEC-001, SEC-002, SEC-014 | Versioned event schema, non-blocking ingestion, overflow metric |
| Rule detection | SEC-003, SEC-005, SEC-007, SEC-008, SEC-009 | Replay tests, explainability, finite TTL and rollback |
| SOC and AI | SEC-006, SEC-010, SEC-011 | Human review, evidence references, shadow-only ML |
| Performance gate | PERF-G0 through PERF-G5 | Representative client workload, logs and signed decision |

All items above are *unimplemented* in the bootstrap.

## Discovery planning artifacts (not implementation evidence)

- D-01: [legacy audit](discovery/LEGACY_AUDIT.md); provisional G-04, RP-004, NET-004, SEC-013, SEC-001/002/014 and PERF-G0.
- D-02: [spike matrix](discovery/TECHNICAL_SPIKE.md); provisional G-04, RP-004, NET-007, SEC-001/002/014, SEC-013, NFR-03 and PERF-G0.
- [ADR draft](adr/0001-discovery-method.md) and [kickoff gates](discovery/KICKOFF_GATES.md): owners TBD; full PRD reconciliation pending.

D-01/D-02 are decision IDs, not newly invented PRD requirements. All mappings
require source confirmation; no audit, benchmark or framework selection has run.
