# Qbox setup for the ledger (draft)

See [ADR 0003](adr/0003-qbox-core-ledger-authority.md). Nothing here has been
run on FXServer yet; record staging results before relying on it.

## Resources and order
Pin versions and record them with their hashes. Neither Qbox nor ox_lib is
vendored here.

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core
ensure sentinel_telemetry
ensure sentinel_admission
ensure rp_economy
ensure rp_qbx_bridge
ensure rp_banking
```

Database: apply `db/migrations` 0000–0003 as well as Qbox's own `qbx_core.sql`.
The game DB user needs `SELECT, EXECUTE` on the ledger tables, plus whatever
Qbox needs for its own tables.

## Required edits in `qbx_core/config/server.lua` (on the host)

1. Route paychecks through the ledger:
   ```lua
   sendPaycheck = function(player, payment)
       local result = exports.rp_qbx_bridge:Paycheck(player.PlayerData.source, payment)
       if result.ok then
           Notify(player.PlayerData.source, locale('info.received_paycheck', payment))
       end
   end,
   ```
   Set `rp_qbx_paycheck_window_s` to `paycheckTimeout * 60` so each paycheck
   has its own idempotency window.
2. Remove `crypto` from `money.moneyTypes`, or keep it out of gameplay; the
   ledger does not cover it.
3. Keep `paycheckSociety = false` until society accounts exist in the ledger.

## Convars

| Convar | Default | Meaning |
|---|---|---|
| `rp_qbx_money_guard` | `enforce` | `observe` allows direct Qbox money changes and reports them |
| `rp_qbx_opening_cash` / `rp_qbx_opening_bank` | 500 / 5000 | Minted once per new character |
| `rp_qbx_paycheck_window_s` | 600 | Must match the Qbox paycheck interval |

## Porting other resources
Never call `exports.qbx_core:AddMoney/RemoveMoney/SetMoney` for cash or bank.
Get account ids with `exports.rp_qbx_bridge:AccountId(citizenid, 'cash'|'bank')`,
move money with `exports.rp_economy:Transfer{...}` and a stable idempotency key,
then call `exports.rp_qbx_bridge:Sync(source)`.

## Staging checks to record
- Run with `rp_qbx_money_guard observe` and list every `ECON-001` signal.
  Each one is a resource that still needs porting.
- New character: ledger accounts opened, opening balances minted once, HUD
  shows the same numbers.
- Bank deposit, withdrawal and transfer at a counter, then the same away from
  a counter (refused), then rapid repeats (rate limited).
- Restart `rp_qbx_bridge` while players are online: balances re-mirror.
