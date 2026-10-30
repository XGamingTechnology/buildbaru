# Operator workflow (draft)

PRD IDs (provisional): SEC-006, SEC-008, SEC-009, SEC-013, NET-004.
Schema: `db/migrations/0002_operator_workflow.*`. Tests: `tests/test_db_ops.py`.
Only the database layer exists. The `sentinel-api` service that authenticates
operators (MFA) and calls these procedures, the SOC UI, and the enforcement
points that read active mitigations are not built yet.

## Roles

| Role | Propose | Approve / reject | Revoke | Manage operators |
|---|---|---|---|---|
| viewer | – | – | – | – |
| analyst | yes | – | own proposals | – |
| responder | yes | – | yes | – |
| approver | yes | yes, with MFA, never own proposal | yes | – |
| admin | yes | yes, with MFA, never own proposal | yes | yes, never self |

Disabled operators can do nothing. The first admin is created by a DBA at
provisioning time; every later change goes through `ops_set_operator` and is audited.

## Mitigation lifecycle

```text
ops_propose ──► proposed ──ops_approve──► active ──ops_revoke──► revoked
                   │  │                      │
                   │  └──ops_reject──► rejected
                   │                         └──expiry──► expired
                   └──ops_revoke / expiry──► revoked / expired
```

- Every mitigation needs a reason, at least one evidence reference, a rollback
  reference, an incident reference and a TTL within its kind's maximum.
- Approval requires a second person (two-person rule) with an active approver
  or admin role and MFA.
- Revoking is deliberately easy: the requester or any responder and above.
- `ops_active_mitigations` hides anything past `expires_at` even before
  `ops_expire_due` runs, so a missed expiry job never extends a mitigation.

| Action kind | Max TTL | Meaning (enforcement not built yet) |
|---|---|---|
| `player_kick_request` | 5 min | request one kick of a pseudonymous session |
| `admission_cooldown` | 1 h | refuse joins of one identity ref temporarily |
| `temp_rate_limit` | 1 h | tighter per-identity rate limit |
| `resource_disable` | 24 h | stop one gameplay resource through change control |
| `watchlist` | 7 days | extra telemetry attention only; no player impact |

There is no permanent ban, IP/ASN block or firewall kind. Adding one requires a
new migration, an ADR and owner approval. AI components may at most draft a
proposal for a human; they never hold an operator role (D-05).

## Guarantees enforced by the database
Triggers enforce these even for direct SQL:
- Evidence, target, reason, requester and rollback reference are immutable.
- Expiry can only move earlier, never be extended.
- Status only moves along the edges above.
- Mitigations and audit rows cannot be deleted. Audit rows cannot be edited.

## Audit trail
Each `ops_audit_log` row stores `prev_hash` and
`row_hash = SHA-256(prev_hash | at (UTC, µs) | actor | action | mitigation_id | detail)`,
starting from 64 zeros. `ops_audit_head` holds the latest hash and serializes
appends. Recomputing the chain (see `assert_chain_valid` in the tests) detects
edits or deletions made by someone who bypasses the triggers. Ship the head
hash off-site periodically so a full rewrite can also be detected (D-08).

## Still open
- sentinel-api authentication, MFA source of truth, DB grants (EXECUTE only).
- Mapping `target_ref` to live sessions in `sentinel_admission` and other enforcement points.
- Retention and export of the audit trail (D-08). Owner sign-off on roles and TTLs.
