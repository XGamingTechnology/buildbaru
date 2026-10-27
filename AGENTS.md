# Codex / coding agent instructions

Source of truth: owner PRD **PRD_FiveM_Sentinel_Full_v1.pdf** (version 1.0, 26 October 2026). The PDF is not stored in this public repo. Read `docs/PRD_CONTEXT.md` for the available summary; ask the owner for the actual PDF when detailed requirements are needed. Treat every proposed capacity, SLO, vendor, and delivery date as *not verified*. Do not invent implementation status.

First inspect repository, read docs, and use narrowly scoped PRs. Work from an issue and include PRD requirement IDs. Do not automatically merge or deploy. Prefer independent, testable modules; server-authoritative economy; versioned migrations; privacy-aware structured telemetry; and conservative admission fallback.

Never commit credentials, game license keys, real player identifiers or raw IP logs, anti-DDoS vendor tokens, or origin details. Do not enable automatic bans or provider firewall actions by AI. Only implement tests against local/synthetic data; obtain authorization for any live network load or security tests. For any change, provide tests, threat/failure checks, rollback, and actual evidence. Do not claim stable 500/1000 CCU without recorded representative results.

Initial task order: discovery/ADRs → P0 controls → RP and Sentinel P1 → closed alpha → benchmark gates. If an implementation requires unknown provider/budget/legacy code details, document the blocker rather than inventing them.
