# D-01 — Legacy audit template

Status: template. Audit LA-001 (inventory) was executed on 2026-10-30; see
[legacy-audit-001.md](legacy-audit-001.md) and the draft
[disposition](LEGACY_DISPOSITION.md). Licensing and security review are still open.
Source: [PRD context](../PRD_CONTEXT.md); the full private PRD is unavailable.
Requirement mappings are provisional: G-04, RP-004, NET-004, SEC-013,
SEC-001/002/014 and PERF-G0. Confirm exact scope against the owner PRD.
Tracking issue: TBD (must be linked before audit execution).
Audit lead: TBD; asset custodian: TBD; licensing reviewer: TBD; security reviewer: TBD.

## Evidence handling

Work on authorized, offline copies. Record provenance and SHA-256 before executing
anything; never run unknown scripts merely to inventory them. Preserve originals.
Use opaque evidence IDs pointing to an access-controlled store; publish only
sanitized summaries. Never include credentials, player identifiers, raw IP logs,
origin endpoints, private topology or vendor protection configuration here.
Unknown is not a pass. Use TBD for unavailable facts and explain the missing evidence.

## Audit header (copy per audit)

| Field | Value |
|---|---|
| Audit ID / date / tracking issue | TBD |
| Custodian authorization / scope / exclusions | TBD |
| Snapshot commit or archive SHA-256 / acquisition method | TBD |
| Sanitized evidence index / access reviewer / retention | TBD |
| Reviewer role / owner role / review date | TBD |

## Resource and asset inventory (copy one row per item)

Include scripts, maps, models, audio, UI, plugins, database migrations and build tools.
An SPDX identifier alone does not prove rights to use or redistribute an asset.

| Item ID / kind / logical path | Version / provenance / SHA-256 | License SPDX expression or UNKNOWN / license evidence / restrictions | Dependencies / pinned versions / FiveM artifact / OneSync assumptions | Performance profile / workload / evidence | Threat exposure / trust boundary / privileges | Reuse recommendation / rationale | Migration / compatibility / rollback | Test evidence / outcome | Risk / owner / disposition |
|---|---|---|---|---|---|---|---|---|---|
| TBD | TBD | UNKNOWN; evidence TBD | TBD | Not measured | Not assessed | Undecided | TBD | Not run | Unknown / TBD / pending |

## Infrastructure inventory (sanitized; copy per component)

| Component ID / function | Version / config digest / evidence ID | Dependency / data classification | Access boundary / backup / restore evidence | Capacity / profiling evidence | Exposure / recovery risk | Owner / disposition |
|---|---|---|---|---|---|---|
| TBD | TBD | TBD | TBD | Not measured | Unknown | TBD / pending |

Keep actual hosts, addresses and operational secrets in the restricted evidence store.
Record DB schema versions, Redis durability assumptions, CI supply chain and recovery
procedures without inventing existing services or provider capabilities.

## Findings and reuse decision (copy per finding)

| Finding ID / affected items / PRD IDs | Observation / evidence / confidence | Severity / likelihood / rationale | Reuse / isolate / rewrite / retire / undecided | Remediation / migration / acceptance test | Owner / reviewer / due date / status |
|---|---|---|---|---|---|
| TBD | Unknown; evidence required | Unrated | Undecided | TBD | TBD / TBD / TBD / open |

Financial paths require server-side authorization, atomic ledger writes, duplicate
request handling, concurrent debit and interrupted-commit tests (G-04, RP-004).
Inspect event spoofing, privilege escalation, dynamic execution and untrusted
third-party dependencies without exploiting any live service.

## Exit and rollback

Cross-check inventory completeness with custodian; reconcile missing files and
hash changes; review licensing and unresolved high risks. Missing rights or source
blocks reuse of that item. Link findings to the [spike](TECHNICAL_SPIKE.md) and
[kickoff gates](KICKOFF_GATES.md). D-01 remains open until authorized reviewers
accept an evidence-backed disposition. Rollback of this document change is a Git
revert; a future migration needs its own tested restore plan. No assets are moved,
installed or deleted by this template.
