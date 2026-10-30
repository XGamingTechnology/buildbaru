# ADR 0002 — Framework-agnostic base before the D-02 spike

Status: Proposed (needs owner review). Date: 2026-10-30.
PRD IDs (provisional, confirm against the full PRD): G-04, RP-002, RP-004,
RP-005, SEC-001, SEC-002, SEC-014, NET-004, SEC-013, D-02, D-08, D-09.

## Context

The owner wants a clean base in this repository first, and to merge the
historical ~2.5 GB server afterwards. D-01 (legacy audit) and D-02 (Qbox vs
custom/legacy core) are still open, so no RP core can be chosen yet.

## Decision

Build only the parts that every candidate core needs and that the PRD marks as
non-negotiable, as standalone resources with no framework dependency:

1. `db/migrations/` — versioned MariaDB migrations, each with a down script.
   0001 provides a double-entry, idempotent, append-only economy ledger. All
   money moves through the `econ_transfer` procedure, which locks accounts in
   id order, rejects overspend, and returns `committed` or `replayed`.
2. `fivem/resources/[rp]/rp_economy` — server-only `Transfer` export over that
   procedure. No client net events. Unknown outcomes return `ECON_UNAVAILABLE`
   and must be retried with the same idempotency key.
3. `fivem/resources/[sentinel]/sentinel_telemetry` — enqueue-only `Emit`
   export, bounded queue with drop counters, async batch shipping, observe
   mode by default, and a guard that refuses identifier/address fields.
4. `contracts/schemas/v1` — closed JSON Schemas for the six PRD §13.2 events.
5. `fivem/server.cfg.example` and `secrets.cfg.example`; real configs are
   git-ignored.

Whichever core D-02 selects will call `exports.rp_economy:Transfer` from its own
server-validated actions instead of mutating balances directly.

## Consequences

- Legacy scripts that change money client-side or via direct SQL `UPDATE` must be
  rewritten to use `Transfer` during the D-01 merge.
- The `oxmysql` dependency is referenced but not vendored; its license and
  version stay pending under D-09.
- Nothing here has run inside FXServer. The oxmysql `CALL` result shape, the
  natives and the exports are unverified until a staging test on FXServer.
- No CCU, SLO or provider claim follows from this change.

## Rollback

Revert the PR. In a database where 0001 was applied, run
`0001_economy_ledger.down.sql` only after a verified backup; it destroys
economy data.
