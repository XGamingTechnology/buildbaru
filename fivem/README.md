# FiveM resources (draft, framework-agnostic)

Nothing here has been run inside FXServer yet. See
[ADR 0002](../docs/adr/0002-framework-agnostic-base.md).

```text
fivem/
  server.cfg.example        # copy to server.cfg on the host (git-ignored)
  secrets.cfg.example       # copy to secrets.cfg on the host (git-ignored)
  resources/
    [sentinel]/sentinel_telemetry   # Emit/GetStats exports, observe mode by default
    [sentinel]/sentinel_admission   # join queue, CGNAT-safe, fail-open (docs/ADMISSION.md)
    [rp]/rp_economy                 # server-only Transfer export over econ_transfer
    [rp]/rp_qbx_bridge              # ledger-authoritative Qbox money (replaces pri_base)
    [rp]/rp_banking                 # bank deposit/withdraw/transfer (replaces pri_banking)
    [dev]/sentinel_selftest         # staging-only smoke checks (deploy/staging), never in production
```

The RP core is Qbox ([ADR 0003](../docs/adr/0003-qbox-core-ledger-authority.md),
[setup](../docs/QBOX.md)). Third-party resources such as `qbx_core`, `ox_lib`
and `oxmysql` are not vendored.

## Rules for every resource
- The server validates every economy and permission change. Clients only send
  requests; they never send amounts or roles that the server trusts.
- Use `exports.rp_economy:Transfer({ from, to, amount, reason, actor, idempotencyKey })`.
  Never `UPDATE` balances directly.
- Emit telemetry with `exports.sentinel_telemetry:Emit(type, fields)` using
  pseudonymous refs only. No license, Steam, Discord, IP or names.
- Do not deploy without an approved game-capable protected endpoint,
  reviewed resources and separate secret storage.
