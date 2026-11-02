# Staging FXServer (not production)

A closed test server on a Linux VPS to check the base inside a real FXServer.
It is not public, has no real players and must use synthetic data only.

## What you need
- Ubuntu 22.04/24.04 with sudo, about 4 GB RAM and 10 GB free disk.
- A FiveM license key from the Cfx.re keymaster, entered on the VPS only.
- The URL of a Linux `fx.tar.xz` from the
  [artifacts page](https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/).
  Use the one marked recommended; Qbox needs build 10731 or newer.
- Release tags for `oxmysql` (<https://github.com/overextended/oxmysql/releases>),
  `ox_lib` (<https://github.com/overextended/ox_lib/releases>) and `qbx_core`
  (<https://github.com/Qbox-Project/qbx_core/releases>). Record all of them in
  the evidence.

## Steps
```bash
git clone https://github.com/XGamingTechnology/buildbaru.git ~/buildbaru-setup
FX_ARTIFACT_URL='<fx.tar.xz URL>' OXMYSQL_VERSION='<tag>' OX_LIB_VERSION='<tag>' QBX_CORE_VERSION='<tag>' \
  bash ~/buildbaru-setup/deploy/staging/setup.sh
nano ~/fxstaging/data/secrets.cfg      # replace CHANGE_ME with the license key
tmux new -s fx
~/fxstaging/buildbaru/deploy/staging/run.sh
```

`setup.sh` does the following. It is safe to re-run.
- Installs MariaDB locally and creates `sentinel_staging`.
- Applies migrations 0000–0003 and Qbox's `qbx_core.sql`.
- Creates an app user with `SELECT, EXECUTE` on the database, plus DML on the
  Qbox tables only. It cannot `UPDATE` or `INSERT` ledger tables.
- Installs `oxmysql`, `ox_lib` and `qbx_core` at the given tags.
- Patches `qbx_core/config/server.lua` so paychecks go through the ledger. If
  the stock code has changed, it prints a warning and you patch it by hand
  (see [docs/QBOX.md](../../docs/QBOX.md)).
- Seeds two synthetic selftest accounts.
- Writes `server.cfg` and `secrets.cfg` (mode 600).

A `server.cfg` from an earlier run is kept. Delete it, or copy in the new
`ensure` lines from `fivem/server.cfg.example`, to pick up Qbox.

## Network
Open port 30120 TCP+UDP **only for your own IP**, in both `ufw` and the cloud
provider's security group. The server is hidden from the public list
(`sv_master1 ""`). No txAdmin and no RCON are configured.

## In-game checks (needs a connected client)

Give your own account admin rights on the host only, by adding
`add_principal identifier.license:<yours> group.admin` to `server.cfg`. Never
commit that line. Then check:

| Check | Expected |
|---|---|
| Create a new character | HUD shows cash 500 / bank 5000; `econ_transactions` has one `open-<citizenid>-cash` and one `open-<citizenid>-bank` |
| `/givemoney <id> bank 100` and `/setmoney <id> cash 1` | Refused (balance unchanged); console shows `blocked direct Qbox ...`; telemetry counts an `ECON-001` signal |
| Same with `set rp_qbx_money_guard observe` | Allowed but reported. Switch back to `enforce` afterwards and restart `rp_qbx_bridge` |
| Wait one paycheck interval while on duty | Bank increases once through `pay-<citizenid>-<window>` |
| At a bank counter: deposit, withdraw, transfer to a second client | Balances move; transfer notifies the receiver |
| Same request away from any counter | `Anda harus berada di bank.` and a `BANK-001` signal |
| More than 5 bank requests in 10 seconds | `Terlalu cepat...` and a `BANK-002` signal |
| `restart rp_qbx_bridge` with players online | Balances re-mirror and nothing changes in the ledger |

Admin money commands are blocked on purpose. Granting money will later go
through the operator workflow (two-person approval), not `/givemoney`.

## Evidence to collect
1. The console block starting with `[selftest]` up to `SUMMARY`. It includes
   the raw oxmysql `CALL` result shape, export round trips, the idempotency
   replay, overspend refusal, reconciliation, DB privilege denial and the
   telemetry privacy guard.
2. Connect from your own FiveM client to `<vps-ip>:30120`. Check that the join
   works in observe mode and that `[sentinel_telemetry] observe mode` counters
   increase. With `sv_maxclients 1` and two clients, check the queue message.
3. Artifact URL and hash, the oxmysql/ox_lib tags and hashes, the qbx_core
   tag and commit, and the repo commit (`setup.sh` prints all of them).
4. The in-game check table above with pass/fail for each row.

Paste these into the PR or issue. Remove any IP address or license key first.

## Reset
`sudo mariadb -e 'DROP DATABASE sentinel_staging'`, delete `~/fxstaging`, then
re-run `setup.sh`. Never point this kit at a production database.
