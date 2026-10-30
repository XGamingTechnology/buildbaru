# D-01 — Legacy audit 001: inventory findings

Status: inventory complete; reuse decisions are a **draft** in
[LEGACY_DISPOSITION.md](LEGACY_DISPOSITION.md) and need owner review.
Template: [LEGACY_AUDIT.md](LEGACY_AUDIT.md). Gates: [KICKOFF_GATES.md](KICKOFF_GATES.md) (K1/K2).

This page is a sanitized summary. It contains file types, counts, sizes,
resource names and flag counts only. No secret values, player identifiers,
IP addresses, player names or file contents. The full inventory
(`inventory.csv`, `resources.csv`, `flags.csv`) stays on the staging host in a
local-only Git repository.

## Audit header

| Field | Value |
|---|---|
| Audit ID / date / tracking issue | LA-001 / 2026-10-30 / TBD |
| Custodian authorization / scope / exclusions | Project owner; whole legacy server folder; archives and `.db` contents not opened |
| Snapshot | `base.rar`, RAR5, not encrypted, 2,636,444,046 bytes, SHA-256 `a65eb079697ef7fee5e1642c53e02fe491b3fd7693866ad15d9f9aa76af37ac7` |
| Acquisition method | Owner upload to staging VPS; extracted with `unrar` (`All OK`) into a read-only folder |
| Completeness check | 28,548 files, 2,887,909,359 bytes: equals the archive listing; 0 read errors |
| Method | Static scan with a stdlib-only Python script; nothing from the base was executed |
| Evidence location | Staging host, local Git commit `416dc7b` (not published) |
| Reviewers | Licensing reviewer TBD; security reviewer TBD |

Limitation: the OS sandbox (bubblewrap) could not start on the host
(`apparmor_restrict_unprivileged_userns`). Protection was the read-only
folder, a non-sudo user and the fact that no base code was run.

## What the base is

- Framework: **ESX** (`es_extended`, referenced by 37 resources). No QBCore or
  Qbox. Two resources reference vRP, whose core is absent (`vrp_taxi` is
  ensured anyway).
- Database library: **`mysql-async`** (23 resources), bundled inside
  `pri_base` and `hybrid_base_backup`; `pri_base` is started as a dependency
  of `es_extended`. `ghmattimysql` (2) and `oxmysql` (1) are also referenced.
- 72 resource directories; 33 are named on `ensure` lines (`server.cfg` 9,
  `resources.cfg` 24). Most server gameplay lives in custom `pri_*` resources.

## Size by category

| Category | Files | Size |
|---|---:|---:|
| Stream assets (maps, vehicles, props) | 4,026 | 1.9 GiB |
| Archives inside the base (not opened) | 45 | 372.5 MiB |
| JS/TS (mostly `node_modules`) | 15,617 | 205.7 MiB |
| Audio | 267 | 73.0 MiB |
| Images | 649 | 64.2 MiB |
| Other | 4,727 | 30.9 MiB |
| Config | 2,221 | 14.3 MiB |
| Executables/binaries | 13 | 10.2 MiB |
| Lua | 830 | 6.8 MiB |
| UI (HTML/CSS) | 120 | 1.5 MiB |
| SQL dumps | 32 | 252 KiB |
| Database files | 1 | 8 KiB |

`node_modules` accounts for 22,399 files (~239 MB). The gameplay code itself is
small: 830 Lua files, 6.8 MiB.

Largest resources: `pri_map` 1.6 GiB (stream), `pri_assets` 561 MiB (stream),
`soulhk_blackjack` 165 MiB, `menuv` 136 MiB (121 MiB `node_modules`),
`screenshot-basic` 85 MiB (82 MiB `node_modules`).

## Flags

Regex and pattern matches; values were never displayed. Counts outside
`node_modules` are what matter for gameplay code.

| Flag type | Total | Outside `node_modules` |
|---|---:|---:|
| secret_license_key | 2 | 2 |
| secret_db_connection | 5 | 5 |
| secret_webhook | 69 | 69 |
| secret_api_key_or_token | 13 | 9 |
| secret_rcon | 2 | 2 |
| player_identifier | 556 | 556 |
| player_data_file | 46 | 46 |
| net_event_money | 678 | 678 |
| dynamic_code | 262 | 31 |
| os_exec | 151 | 6 |
| external_http | 54 | 54 |
| ip_address | 988 | 158 |
| obfuscation | 4,868 | 2,704 |
| escrow (`.fxap`) | 0 | 0 |

`net_event_money` means a network event handler and a money call share a
server file. It marks code to review, not a proven exploit.

### Where the sensitive flags are

| Location | Secrets | Player identifiers / data files |
|---|---|---|
| `server.cfg`, `server.cfg.bkp` (root) | license key, DB connection, tokens | identifiers in permissions lines |
| `permissions.cfg` (root) | 1 token | 9 identifiers |
| `resources/[BOT]/discordbott*` | bot tokens | — |
| `essentials` | 31 webhooks | 11 identifiers |
| `es_extended` | 12 webhooks | 1 data file |
| `gksphone`, `gcphone`, `pri_property`, `pri_banking`, `pri_housing`, `BanSql`, `rgz_playedtime-main` | webhooks; 1 DB string in `gksphone` | data files |
| `EasyAdmin` | 2 webhooks | 505 identifiers, 11 data files (ban lists) |
| `vmenu_bans.db`, `StreetRaces_saveData.txt` (root) | not scanned | player data |

## Highest-risk resources

Ranked by weighted flag counts outside `node_modules`. This orders review, it
does not prove a resource is malicious.

| # | Resource | Main reasons |
|---:|---|---|
| 1 | `EasyAdmin` | 505 player identifiers, 11 data files, 20 money events |
| 2 | `essentials` | 31 webhooks, 28 money events, 11 identifiers |
| 3 | root configs and `discordbott` | license keys, DB strings, tokens, 21 identifiers |
| 4 | `gksphone` | 77 money events, 8 webhooks, 1 DB string |
| 5 | `pri_banking` | 46 money events, 13 identifiers |
| 6 | `pri_property` | 25 money events, 6 data files, 3 webhooks |
| 7 | `es_extended` | 31 money events, 12 webhooks |
| 8 | `gcphone` | 8 data files, 16 money events, 4 webhooks |
| 9 | `pri_housing` | 30 money events, 2 dynamic code, 2 webhooks |
| 10 | `pri_jobs` | 158 money events |
| 11 | `pri_vehicle` | 56 money events |
| 12 | `pri_personal` | 58 money events, 6 external HTTP calls |
| 13 | `yarn` (stock builder) | 5 process executions |
| 14 | `pri_nonwhitelistjobs` | 6 data files, 6 money events |
| 15 | `runcode` (stock) | 2 RCON flags, dynamic code |

## Archives inside the base

45 archives were not opened (372.5 MiB). The largest are map packs inside
`pri_map/stream` (about 300 MiB in 7 archives). The others are older copies or
duplicates of resources (`es_extended`, `gksphone`, `menuv`, `hybrid_*`),
small config and job fragments inside `pri_jobs`, `pri_doorlock` and
`essentials`, and 10 vendored `.tgz` files in `node_modules`. One phone-script
archive's filename suggests that its license protection was removed. It must
not be reused, and a legitimately licensed copy is required instead (D-09).

## Immediate actions (owner)

1. **Rotate everything that was ever in this base.** That covers the FiveM
   license key, database passwords, all Discord webhooks (delete and recreate),
   bot tokens and the RCON password. Treat every one as exposed.
2. **Keep player data out of the new project.** That covers ban lists, saved
   data and identifiers in configs. Whether any of it may be migrated is a
   privacy decision (D-08).
3. **Do not run this base on a reachable server.**

## Unknowns

- Contents of the 45 archives and of `vmenu_bans.db`.
- Which secret flags are real values and which are placeholders.
- Licenses for paid or third-party resources and for map/vehicle assets (D-09).
- Player names, which cannot be detected by pattern.
- Runtime behaviour: nothing was executed, so exploitability is unconfirmed.
