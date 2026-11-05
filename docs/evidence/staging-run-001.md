# Staging run 001 — in-server selftest

Date: 2026-11-05. Host: owner's staging VPS (Ubuntu 24.04), closed test, synthetic
data only. No players connected. Repo `main` at `fd69621` (PR #12).

## Versions

| Component | Version / hash |
|---|---|
| FXServer | `FXServer-master v1.0.0.35245 linux` |
| MariaDB | 10.11.14 |
| oxmysql | installed 2026-10-30 (tag not recorded; record on next run) |
| ox_lib | v3.42.0, zip SHA-256 `218f870fbe3f7334233592fdb21bd93a14a78808e286a9d9ac1ec89c9181a7d4` (bundles `require` 1.0.2) |
| ox_inventory | v2.48.1 |
| qbx_core | v1.24.1 (`5e43f63`), `sendPaycheck` patched to `rp_qbx_bridge:Paycheck` |

## Result: `[selftest] SUMMARY PASS 30/30`

Verified inside FXServer:
- Ledger through the `rp_economy` export: commit, idempotent replay (same `txId`),
  `ECON_IDEMPOTENCY_CONFLICT`, `ECON_INSUFFICIENT_FUNDS`, `ECON_INVALID_AMOUNT`
  for 1.5, reconciliation sum = 0. Integers survive the export boundary.
- oxmysql returns `CALL` results as `[[row], header]`; `extractCallRow` and
  `firstRow` handle this shape.
- Least privilege: the app DB user gets `UPDATE command denied` on
  `econ_accounts`.
- Telemetry accepts a valid event and refuses an IP field.
- Operator workflow view is readable.
- Qbox stack: `ox_lib`, `ox_inventory`, `qbx_core`, `rp_qbx_bridge` and
  `rp_banking` are started. `inventory:framework` is `qbx` and
  `inventory:accounts` is `[]` (cash is not an item). Paychecks are routed
  through the ledger, and all three money guard hooks are registered.
- Bridge: one account per character and type, the opening balance is minted
  exactly once, an invalid citizenid and `crypto` are refused, and the ledger
  still reconciles after minting.

## Findings fixed on the way (PRs #11, #12)
1. `ox_lib` 3.42 needs its bundled `require` resource. `setup.sh` now installs
   every resource in a release zip.
2. `qbx_core` changes its own schema at start (`users`, `players.userId`).
   Table-scoped grants allow this while ledger tables stay locked.
3. `qbx_core` requires `ox_inventory` ≥ 2.42.1 and `inventory:framework "qbx"`,
   and on any startup error it runs `quit immediately`, which caused the earlier
   crashes.
4. The bridge now retries hook registration until `qbx_core` answers.

## Not yet verified (needs connected clients; see deploy/staging/README.md)
Money guard against `/givemoney` and `/setmoney`, paycheck, bank at and away
from a counter, rate limit, transfer between players, bridge restart with
players online, admission and queue behaviour, and any CCU or performance figure.
