# PRD source context (summary; not a substitute for the full PRD)

**Source:** Owner-uploaded `PRD_FiveM_Sentinel_Full_v1.pdf`, 21 pages, dated 26 October 2026. Status in source: proposed, not approved. The private attachment has not been published to this repository.

## Product objective
Build one Indonesian FiveM RP world on a single FXServer/OneSync instance, integrating a modular roleplay platform and an out-of-band Sentinel Security Platform. Candidate stack (not final): Qbox after technical spike; Lua/TypeScript for gameplay; Rust/Tokio/Axum for Sentinel; MariaDB persistent data; Redis ephemeral; React/TypeScript NUI and SOC panel; txAdmin for game operations.

## Capacity and security
- First stable gate: 500 CCU with representative tests; 750–1,000 CCU is later experimental capacity, not a guarantee.
- DDoS L3/L4 volumetric mitigation belongs at the upstream provider supporting FiveM TCP/UDP traffic.
- Join scoring must handle shared IP/CGNAT fairly and be fail-safe when Sentinel is unavailable.
- Economy/state changes must be server-authoritative, transactional, idempotent and auditable.
- AI begins with rules / offline shadow evaluation / evidence-grounded summaries; no direct permanent ban or broad firewall control.

## Initial gates
PRD §16: PERF-G0 32–64 QA sessions, G1 128 CCU, G2 256 CCU, G3 500 CCU plus hotspot/steady state, G4 750 experimental, G5 1,000 extended stress. Proposed test duration and SLO must be reviewed and evidenced. No live destructive, network, or DDoS testing without owner and provider authorization.

## Unknowns
Historical source code and incident forensics, licensing, hosting vendor, budget, staffing, RP category, production domain, support processes, privacy and monetization decisions remain unresolved. See `docs/DECISIONS.md`. Do **not** make up values in implementations.
