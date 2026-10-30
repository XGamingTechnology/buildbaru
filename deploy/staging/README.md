# Staging FXServer (not production)

A closed test server on a Linux VPS to check the base inside a real FXServer.
It is not public, has no real players and must use synthetic data only.

## What you need
- Ubuntu 22.04/24.04 with sudo, about 4 GB RAM and 10 GB free disk.
- A FiveM license key from the Cfx.re keymaster, entered on the VPS only.
- The URL of a Linux `fx.tar.xz` from the
  [artifacts page](https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/)
  (use the one marked recommended), and an `oxmysql` release tag from
  <https://github.com/overextended/oxmysql/releases>. Record both in the evidence.

## Steps
```bash
git clone https://github.com/XGamingTechnology/buildbaru.git ~/buildbaru-setup
FX_ARTIFACT_URL='<fx.tar.xz URL>' OXMYSQL_VERSION='<tag>' bash ~/buildbaru-setup/deploy/staging/setup.sh
nano ~/fxstaging/data/secrets.cfg      # replace CHANGE_ME with the license key
tmux new -s fx
~/fxstaging/buildbaru/deploy/staging/run.sh
```

`setup.sh` installs MariaDB locally, creates `sentinel_staging` with an app user
that has only `SELECT, EXECUTE` (it cannot `UPDATE` balances), applies
migrations 0000–0002, seeds two synthetic selftest accounts, links the resources
and writes `server.cfg` and `secrets.cfg` (mode 600). It is safe to re-run.

## Network
Open port 30120 TCP+UDP **only for your own IP**, in both `ufw` and the cloud
provider's security group. The server is hidden from the public list
(`sv_master1 ""`). No txAdmin and no RCON are configured.

## Evidence to collect
1. The console block starting with `[selftest]` up to `SUMMARY`. It includes
   the raw oxmysql `CALL` result shape, export round trips, the idempotency
   replay, overspend refusal, reconciliation, DB privilege denial and the
   telemetry privacy guard.
2. Connect from your own FiveM client to `<vps-ip>:30120`. Check that the join
   works in observe mode and that `[sentinel_telemetry] observe mode` counters
   increase. With `sv_maxclients 1` and two clients, check the queue message.
3. Artifact URL and hash, oxmysql tag and hash, and the repo commit
   (`setup.sh` prints all of them).

Paste these into the PR or issue. Remove any IP address or license key first.

## Reset
`sudo mariadb -e 'DROP DATABASE sentinel_staging'`, delete `~/fxstaging`, then
re-run `setup.sh`. Never point this kit at a production database.
