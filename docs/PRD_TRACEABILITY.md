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

All items above were *unimplemented* in the bootstrap.

## Draft progress (not acceptance)

| Slice | Draft artifact | Evidence so far | Still missing |
|---|---|---|---|
| Economy integrity | `db/migrations/0001_*`, `fivem/resources/[rp]/rp_economy` | MariaDB tests: atomic transfer, idempotent replay, concurrent debit/duplicate, lock timeout, append-only, reconciliation | FXServer/oxmysql run, restore drill, review |
| Telemetry | `contracts/schemas/v1`, `fivem/resources/[sentinel]/sentinel_telemetry` | Schema + negative fixtures; Lua queue bound and privacy guard unit tests | FXServer run, ingest service, retention (D-08) |

See [ADR 0002](adr/0002-framework-agnostic-base.md). Passing these tests is not
acceptance of any PRD requirement.
