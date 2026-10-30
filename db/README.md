# Database migrations (MariaDB)

Versioned, forward-only files with a paired down script. Apply in order with
the `mariadb`/`mysql` CLI (the files use `DELIMITER`):

| Version | Up | Down | PRD IDs |
|---|---|---|---|
| 0000 | `0000_schema_migrations.up.sql` (idempotent bookkeeping) | none | — |
| 0001 | `0001_economy_ledger.up.sql` | `0001_economy_ledger.down.sql` (destroys economy data) | RP-002, RP-004, RP-005, G-04 |
| 0002 | `0002_operator_workflow.up.sql` | `0002_operator_workflow.down.sql` (destroys the audit trail; export first) | SEC-008, SEC-009, SEC-013 |

## Economy rules enforced by the database
- Money moves only via `CALL econ_transfer(key, from, to, amount, reason, actor)`.
- Every transfer is two ledger entries that sum to zero; the system `treasury`
  account is the only one allowed to go negative (mint/burn source).
- Same idempotency key + same request → `replayed`, never a second debit.
  Same key + different request → `ECON_IDEMPOTENCY_CONFLICT`.
- `econ_transactions` and `econ_ledger_entries` are append-only (triggers).
  Corrections are new compensating transfers.
- Reconciliation check: `SUM(balance)` over all accounts is 0, and each balance
  equals the sum of its ledger deltas (see `tests/test_db_ledger.py`).

Use a least-privilege application user in production (EXECUTE on the
procedure, SELECT where needed); grants are pending NET-004/SEC-013.

Operator roles, mitigation lifecycle and the hash-chained audit log are
described in [`docs/OPERATOR_WORKFLOW.md`](../docs/OPERATOR_WORKFLOW.md).
