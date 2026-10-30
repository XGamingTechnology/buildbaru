# ADR 0003 — Qbox as RP core, econ ledger as money authority

Status: Accepted by the project owner (2026-10-30) for implementation; the
D-02 spike evidence (staging run) is still to be recorded.
PRD IDs (provisional): D-02, G-04, RP-002, RP-004, RP-005, SEC-003, SEC-005.

## Context

The legacy base runs ESX with `mysql-async` and 678 places where network
events and money calls share a server file
([LA-001](../discovery/legacy-audit-001.md)). The PRD names Qbox as the
candidate core. [ADR 0002](0002-framework-agnostic-base.md) kept the base
framework-agnostic with an append-only ledger (`econ_transfer`) as the only way
to move money.

Qbox (`qbx_core` 1.24.0, checked at commit `58b345e`) stores money in
`PlayerData.money` and exposes `AddMoney`/`RemoveMoney`/`SetMoney`. Before
each change it calls registered **event hooks** (`addMoney`, `removeMoney`,
`setMoney`). A hook that returns `false` cancels the change. Paychecks go
through the configurable `config.sendPaycheck` in `qbx_core/config/server.lua`.

## Decision

1. **Qbox is the RP core** (`qbx_core` + `ox_lib` + `oxmysql`). ESX resources
   are rewritten, not ported.
2. **The ledger is authoritative for `cash` and `bank`.** Qbox
   `PlayerData.money` is a mirror for HUDs and compatibility only.
3. `rp_qbx_bridge` (replaces legacy `pri_base`):
   - opens per-character ledger accounts through `econ_open_account`
     (migration 0003) and mints opening balances from the treasury,
     idempotently;
   - mirrors ledger balances into Qbox with `SetMoney`;
   - registers the three money hooks. In `enforce` mode (the default) every
     direct change to `cash`/`bank` from another resource is cancelled and
     reported as `game_abuse_signal` `ECON-001`. `observe` mode allows and
     reports, and is for staging diagnosis only;
   - exposes `Paycheck(source, amount)` so `config.sendPaycheck` pays through
     the ledger.
4. `rp_banking` (replaces legacy `pri_banking`) does deposit, withdrawal and
   player-to-player transfer as ledger transfers. The server validates the
   character, an integer amount, a per-character rate limit, the player's
   distance to a bank counter, and a client request id that becomes the
   idempotency key.
5. Money types outside the ledger (Qbox `crypto`) are not used until a ledger
   currency exists for them.

## Consequences

- Third-party Qbox resources that call `AddMoney`/`RemoveMoney` directly will
  fail in `enforce` mode until they are ported to `rp_economy` Transfer. This
  is intended, and each port is reviewed. Staging can use `observe` to find
  them.
- `qbx_core/config/server.lua` must be edited on the host (see
  [QBOX.md](../QBOX.md)); the repo does not vendor Qbox.
- Licensing (D-09): `qbx_core` is GPL-3.0 per its LICENSE file. `ox_lib` and
  `oxmysql` licenses still need to be confirmed before distribution decisions.
- Unverified until staging: cross-resource hook calls, `SetMoney` from the
  bridge passing its own guard, oxmysql `CALL` result shape, and exports
  crossing resource boundaries with integer amounts.

## Rollback

Set `rp_qbx_money_guard observe`, or stop `rp_qbx_bridge` and `rp_banking`.
Qbox then manages money on its own again, but ledger balances and Qbox balances
will diverge and must be reconciled before re-enabling. Revert the PR to drop
the code; migration 0003 has a down script.
