# Project Sentinel RP

Starter repository based on **FiveM Sentinel PRD v1.0 (26 October 2026)**. This is a **planning/contract-only scaffold**, not a deployed game or security product.

## Goals
- Build Indonesian FiveM RP with FXServer/OneSync and modular Lua/TypeScript gameplay.
- Develop Rust-based Sentinel telemetry, policy and internal API alongside SOC dashboard.
- Validate **500 CCU** in representative tests; **1,000 CCU** is an unproven stretch goal.

## Non-negotiable boundaries
- Upstream DDoS scrubbing is the job of a verified provider with supported FiveM game traffic, *not* a web CDN or an AI model.
- The FXServer validates all economy and permission mutations on the server; use transactional persistence and idempotency.
- The Sentinel/LLM never issues permanent bans, broad IP/ASN blocks, firewall changes, or shell commands autonomously.
- Shared IPs may be CGNAT; do not treat an IP address as a unique player identity.
- Protect admin/DB/Redis endpoints, maintain backup/restore drills and publish no real secrets.

## Start here
1. Read `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/PRD_TRACEABILITY.md`.
2. Capture outstanding design decisions in `docs/DECISIONS.md`.
3. Do discovery and a provider PoC **before** claiming the first public release.
4. Use a branch + PR; merge only after CI, review, and evidence-based acceptance criteria.

The full owner-provided PRD PDF is held outside this public repository. See `docs/PRD_CONTEXT.md` for a source-limited summary; obtain the original PRD from the project owner before changing scope.

This repository intentionally contains *no* production FXServer config, server credentials, sensitive protection rules, or live AI actions.
