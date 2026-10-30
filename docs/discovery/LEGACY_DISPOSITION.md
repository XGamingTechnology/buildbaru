# D-01 — Legacy resource disposition (draft)

Status: **proposal for owner review**; nothing is decided or moved yet.
Evidence: [legacy-audit-001.md](legacy-audit-001.md). Architecture:
[ADR 0002](../adr/0002-framework-agnostic-base.md). Licensing: D-09. Privacy: D-08.

The rule of thumb: gameplay ideas, configs, UI and assets can be carried over;
server logic that touches money, roles or player data is rewritten on the new
base (`rp_economy` Transfer, server-side validation, telemetry). Stock and
open-source resources come fresh from their upstream releases instead of the
copies in the old base.

| Disposition | Meaning |
|---|---|
| **Reuse after review** | Keep the files after a license check and a read-through; no rewrite expected |
| **Upstream** | Use a fresh, pinned upstream release; do not copy the legacy folder |
| **Rewrite** | Keep as a functional reference (configs, UI, design); reimplement server logic on the new base |
| **License first** | Third-party or paid resource; no reuse until a valid license for this project is confirmed |
| **Retire** | Do not migrate |

"Ensured" means named on an `ensure`/`start` line of the legacy configs.

## Reuse after review (assets)

| Resource | Ensured | Size | Notes |
|---|---|---:|---|
| `pri_map` | yes | 1.6 GiB | Custom map stream; 7 map archives inside (≈300 MiB) to evaluate; author and license per asset needed |
| `pri_assets` | yes | 561 MiB | Add-on stream assets (vehicles/props); same license check; 2 archives inside |
| `pri_ipl` | yes | 0.3 MiB | IPL loader, standalone, no flags |
| `interactsound` | yes | 3.4 MiB | Common open-source sound helper; prefer upstream release if licensing is unclear |
| `xsound` | yes | 2.5 MiB | Open-source audio library; prefer upstream release |

## Upstream (stock FiveM and maintained libraries)

| Resource | Ensured | Notes |
|---|---|---|
| `spawnmanager`, `mapmanager`, `sessionmanager`, `baseevents`, `hardcap`, `chat`, `scoreboard`, `playernames`, `rconlog` | partly | From the pinned `cfx-server-data` release that matches the chosen artifact |
| `screenshot-basic` | yes | Upstream release; the legacy copy carries 82 MiB of `node_modules` |
| `webpack`, `yarn` | no | Build helpers; only if an upstream resource needs them |
| `menuv` (+ `app`, `example`, `menuv_example`) | no | Upstream release if a menu library is still needed; examples dropped |
| `vMenu` | yes | Upstream release; staff-only permissions; **do not migrate `vmenu_bans.db`** |
| `EasyAdmin` | no | Upstream release, or replace with the SOC operator workflow; **do not migrate its 505 identifiers / ban data** |

## Rewrite on the new base

Ordered roughly by dependency. All of these depend on ESX, so the target core
(ESX legacy vs Qbox vs custom) must be decided first in the D-02 spike.

| Resource | Ensured | Money events | Other flags | Notes |
|---|---|---:|---|---|
| `es_extended` | yes | 31 | 12 webhooks | Framework core: replaced by the D-02 choice, not carried over |
| `pri_base` | no (dependency) | 0 | DB string | Replaced by `rp_qbx_bridge` + `oxmysql` + migrations (ADR 0003) |
| `pri_core` | yes | 14 | — | Core gameplay glue |
| `pri_depencies` | yes | 11 | — | Shared helpers; review what is still needed |
| `essentials` | yes | 28 | 31 webhooks, 11 identifiers | Large script pack (108 Lua); split by feature |
| `pri_banking` | yes | 46 | 13 identifiers | Replaced by `rp_banking` (ADR 0003) |
| `pri_jobs` | yes | 158 | 8 archives inside | Highest money-event count; job payouts via Transfer |
| `pri_nonwhitelistjobs` | yes | 6 | 6 data files | Same as jobs |
| `pri_vehicle` | yes | 56 | — | Purchases and ownership via Transfer |
| `pri_property` | yes | 25 | 6 data files, webhooks | Property purchases/rent |
| `pri_housing` | no | 30 | dynamic code | Overlaps `pri_property`; merge |
| `pri_personal` | yes | 58 | 6 external HTTP | Review every outbound call |
| `pri_personalui` | yes | 5 | — | UI can be reused |
| `pri_illegal` | yes | 40 | — | Illegal activities; anti-abuse signals (SEC-003/005) |
| `pri_robbery` | yes | 8 | — | Same |
| `pri-starterpack` | yes | 6 | data file | One-time grant must be idempotent |
| `pri_doorlock` | yes | 0 | 2 archives inside | Server-side authorization for doors |
| `pri_hud`, `pri_menu`, `pri_nativeui`, `pri_modernui`, `pri_radialmenu`, `pri_chat` | yes | 0 | minor | Mostly UI; reuse layouts and assets |
| `boombox` | yes | 0 | 2 data files | Small; rewrite or upstream |
| `gks_gotur`, `iprp_winstar`, `esx_lapraces` | no | 13 / 10 / 20 | data files | Not ensured; only if the features are wanted |

## License first (third-party)

| Resource | Ensured | Notes |
|---|---|---|
| `gksphone` | yes | Paid phone script; 77 money events. The legacy archive's filename suggests license protection was removed, so a legitimately licensed copy is required |
| `gcphone` | no | Alternative phone; pick one phone only |
| `rcore_pool` | no | Paid; heavy obfuscation flags |
| `soulhk_blackjack` | no | Gambling also needs a policy decision (D-06) |
| `adminmenu` | no | Port of an admin menu for ESX; prefer the SOC operator workflow |

## Retire

| Item | Reason |
|---|---|
| `hybrid_base_backup`, `hybrid_hud_backup` | Backups of other resources |
| `hybrid_nohelmet` | Trivial; reimplement in a few lines if wanted |
| `vrp_taxi` | Needs vRP, which is not present; ensured but cannot work |
| `discordbott`, `discordbott2`, `discordbott3`, `RichPresence` | Bot tokens; rebuild later with secrets outside the code if needed |
| `BanSql`, `rgz_playedtime-main` | Player identity data and webhooks; replaced by admission + operator workflow and telemetry |
| `runcode` | Remote code execution tool; never on a live server |
| `basic-gamemode`, `fivem`, `fivem-map-hipster`, `fivem-map-skater`, `redm-map-one`, `example-loadscreen`, `sessionmanager-rdr3` | Stock examples or RedM-only |
| All top-level archives and old copies | Duplicates of resources above |
| `server.cfg`, `server.cfg.bkp`, `permissions.cfg` | Contain secrets and identifiers; recreate from `fivem/server.cfg.example` |
| `vmenu_bans.db`, `StreetRaces_saveData.txt` | Player data (D-08) |
| All `node_modules` folders | Build output; restore from package manifests only if needed |

## Proposed order once approved

1. Owner rotates every secret listed in the audit.
2. Owner decides D-02 (core framework); D-09 licensing review of `pri_map`,
   `pri_assets` and the "license first" list.
3. Import approved assets (`pri_map`, `pri_assets`, `pri_ipl`) into a private
   asset store, referenced by a manifest with hashes. They are not committed
   to this public repository.
4. Rewrite in this order: core and DB (`pri_base` → `oxmysql`), banking and
   starter pack, jobs, vehicles, property and housing, illegal and robbery,
   then UI resources. Each one is a separate PR with Transfer-based tests.
5. Add upstream resources with pinned versions as each feature needs them.

Rollback: this is a planning document. Reverting it changes nothing on any server.
