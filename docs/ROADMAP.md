# Delivery plan — proposed, not committed

## Phase 0: Discovery & evidence
- [ ] Inventory old assets, licenses, security concerns and code reuse decision (D-01).
- [ ] Run Qbox vs legacy/custom technical spike (D-02).
- [ ] Evaluate provider capability for protected HTTPS connect and FiveM TCP/UDP game path; prove no public origin bypass (NET-001/002/003/008).
- [ ] Confirm people, costs, location, RP focus, policy and monetization choices (D-03/D-06/D-10).

## Phase 1: Foundation / P0
- [ ] Set up local/staging/production separation, approval-based CI/CD and backups.
- [ ] Private admin/DB/Redis endpoints, permissions and MFA plan (NET-004, SEC-013).
- [ ] Character persistence, role server-checks and auditable economy ledger (G-04).
- [ ] Observability, provider/FXServer/DB telemetry and safe overflow behavior (SEC-001/002/014).
- [ ] Verify failure-safe admission and session survivability (NET-007, NFR-03).

## Phase 2: P1 gameplay + Sentinel
- [ ] RP-001 to RP-010, RP-014, plus required P0 RP-015.
- [ ] NET-005/006/010, SEC-003 to SEC-009; SOC dashboard, no unsafe auto enforcement.
- [ ] QA negative tests: transfer retry, duplicate events, forged roles, CGNAT, DB disconnect.

## Phase 3: Evidence-gated capacity and AI
- [ ] PERF-G0: 32–64 QA sessions.
- [ ] PERF-G1/G2: 128 and 256 representative CCU tests.
- [ ] PERF-G3: 500 CCU 60–120 min steady + crowd hotspot; report SLO and economy integrity.
- [ ] PERF-G4/G5: 750 then 1,000 non-public stress tests *only after preceding gates*.
- [ ] SEC-010/011/012: shadow ML and read-only AI summarizer with evaluation/uncertainty.

No infrastructure procurement or production deployment is authorized by this scaffold.
