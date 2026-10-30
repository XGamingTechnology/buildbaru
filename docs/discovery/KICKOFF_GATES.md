# D-01 / D-02 — Evidence and kickoff gates

All gates are pending; role owners and tracking issue are TBD. A checked box must
link dated evidence, reviewer role, outcome and remaining risks. Do not check a
gate merely because this document exists. See [audit](LEGACY_AUDIT.md),
[spike](TECHNICAL_SPIKE.md), [ADR](../adr/0001-discovery-method.md) and
[traceability](../PRD_TRACEABILITY.md).

| Gate | Required evidence / PRD IDs | Accountable role | State / evidence |
|---|---|---|---|
| K0 source and scope | Full private PRD reviewed; provisional ID mappings and SLOs reconciled; issue linked; no private attachment committed; D-01/D-02 | Product owner TBD | Pending / TBD |
| K1 authorized inventory | Custodian scope, immutable snapshot hashes, dependency/resource completeness, missing items recorded; D-01 | Asset custodian TBD | Pending / TBD |
| K2 rights and exposure | License/SPDX review and restricted threat findings; reuse exclusions; D-09, NET-004, SEC-013 | Licensing and security reviewers TBD | Pending / TBD |
| K3 lab readiness | Isolation, synthetic data, privacy retention, fixed candidate versions and workload/budgets/score checklists; D-02, D-08/D-10 | Spike and operations leads TBD | Pending / TBD |
| K4 approval to start spike | K0–K3 accepted; people/effort budget approved; no procurement or production authorization implied; D-02 | Product owner TBD | Pending / TBD |
| K5 evidence review after spike | Repeated measurements, negative tests, hard gates, scores, migration/restore evidence and unresolved risks; G-04, RP-004, NET-007, SEC-001/002/014 | QA and security reviewers TBD | Pending / TBD |
| K6 architecture decision | D-01 disposition and D-02 recommendation reviewed in superseding ADR; next implementation issue; PERF gates still unproven | Architecture and product owners TBD | Pending / TBD |

## Evidence record (copy per gate)

- Gate / issue / run ID / UTC date: TBD
- PRD IDs / original requirement confirmation: TBD
- Sanitized artifact reference / SHA-256 / reproduction command: TBD
- Actual outcome (pass, fail, skipped, unrun) / limitations: unrun
- Threat/failure review / privacy handling / rollback evidence: TBD
- Accountable role / independent reviewer / approval date: TBD
- Residual risk / follow-up issue / expiry or revisit trigger: TBD

Missing legacy access, rights, budget, full PRD or assigned reviewers blocks only
the affected gate and must remain explicit. Current changes provide templates,
not audit findings or kickoff approval. Revert documents to roll back this slice;
future experiments require their own approved cleanup and recovery steps.
