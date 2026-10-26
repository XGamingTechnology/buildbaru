# D-02 — Qbox versus legacy/custom technical spike

Status: proposed plan; no candidate installed, measured or selected.
Tracking issue: TBD; spike lead / QA / security / licensing / operations reviewers: TBD.
Use [D-01 inventory](LEGACY_AUDIT.md), [PRD context](../PRD_CONTEXT.md) and
[ADR draft](../adr/0001-discovery-method.md). Full PRD confirmation is required
before fixing acceptance SLOs or changing product scope.

## Candidate and experiment manifest

Compare Qbox, an available legacy baseline, and a scoped custom prototype separately.
Absent legacy source means unavailable, not a zero score or an invented baseline.
Record for each: repository/version/commit and SHA-256, license evidence, resource
set and dependency lock, FXServer artifact, OneSync mode, OS/hardware allocation,
DB/Redis versions if used, configuration digest, harness revision, synthetic seed,
run ID/date, operator, commands, durations, raw evidence IDs and known exclusions.
Do not download frameworks as part of this documentation task.

Before execution, approve an isolated local/lab scope, synthetic accounts, minimal
identical gameplay slice, workload schedule, resource budget, run duration, warmup,
hitch threshold in milliseconds, latency/CPU/memory budgets and recovery RTO/RPO.
All numerical acceptance budgets are TBD and must be frozen before results are seen.
Run at least three measured repetitions per candidate after the same warmup;
report individual values, median, p95/p99 where sampled, sample count and variance.
Randomize candidate order and explain differing dependencies or unsupported features.
Record failures and exclusions; do not silently omit a bad run. Client simulation
limitations must be explicit; synthetic concurrency is not representative CCU proof.

## Evaluation matrix

All candidate measurements, evidence links and scores are TBD. Weights total 100.
Each row needs a result per candidate, a reviewer and a reproducible evidence ID.

| Criterion / PRD mapping | Weight | Measurement / acceptance evidence |
|---|---:|---|
| FiveM / OneSync compatibility; D-02, RP-001 | 12 | Pinned artifact and native/resource compatibility checklist; spawn, reconnect and state sync pass counts; unsupported APIs listed |
| Performance / hitch; PERF-G0 | 15 | Identical idle, transaction, reconnect and crowd workloads; tick/hitch count per minute above frozen threshold, p95/p99 tick and latency, CPU/RSS; compare against frozen budgets |
| Maintainability; D-01/D-02 | 10 | Same bounded change exercised by each candidate; engineer hours, touched modules, regression count, upgrade/review evidence |
| License and provenance; D-01/D-09 | 10 | Percentage of included items with reviewed rights and SPDX or explicit proprietary terms; unresolved redistribution restrictions; license reviewer signoff |
| Asset inventory / migration fit; D-01, RP-004 | 8 | Required audited items compatible / total, conversion effort in person-days with range, lost features and migration reconciliation results |
| Economy integrity; G-04, RP-004 | 15 | Server-authoritative debit/credit; retry same key, concurrent insufficient balance, conflicting key payload, DB failure before/after commit; zero duplicate writes, unauthorized writes or unbalanced ledger entries |
| Security / telemetry failure; NET-007, SEC-013, SEC-001/002/014 | 12 | Forged roles/events rejected; privilege review; synthetic collector outage/overflow bounded without blocking game ticks; no autonomous bans/firewall actions; unresolved finding counts |
| Cost / effort; D-10 | 6 | Itemized license/operations costs and implementation/migration person-days, ranges, assumptions and dated quote evidence; no procurement |
| Recovery; G-04, NFR-03 | 6 | Synthetic snapshot restore and interrupted migration; measured RTO/RPO against frozen budgets; ledger reconciliation and rollback evidence |
| QA / reproducibility; PERF-G0, RP-004 | 6 | Same scenario assertions and pass/fail/skip counts; clean-environment reproduction by a second reviewer; evidence completeness |

## Auditable scoring and decision rule

Before execution, give each row a binary checklist of mandatory assertions plus
optional assertions, quantitative target/baseline and named role reviewer. Record
these in the run manifest; do not adjust weights or budgets after seeing results.
Score 0: executed and mandatory assertions fail without a bounded remediation.
Score 1: mandatory failure with evidenced bounded remediation, still not acceptable.
Score 2: all mandatory assertions pass; optional assertions fail or remain untested.
Score 3: all mandatory and optional assertions pass in all three measured runs.
Score 4: score 3 plus independent clean-environment reproduction and reviewed evidence.
Missing measurements are UNKNOWN, never zero and never an implicit pass.
Weighted total = sum(weight * score / 4), range 0–100, only when all rows are scored.

Hard gates override totals: legal rights for every included asset; no unresolved
critical security finding; every economy invariant test passes; approved recovery
budgets pass; required compatibility scenarios pass. Unknown hard gates block a
recommendation. Record severity rubric and signoff before testing; no candidate
can trade economy safety or license rights for speed.

Eligible candidates need all hard gates and a proposed minimum 75/100, subject to
review before execution. A difference below 5 points, overlapping measurement
uncertainty or effort ranges triggers a documented follow-up rather than a winner.
A single eligible candidate still requires explicit architecture/owner review.
If none qualifies, retain D-02 open and propose a bounded additional spike.
Publish per-row score, evidence, dissent and assumptions; no winner before data.

## Threat, failure, benchmarks and rollback boundaries

Use synthetic fixtures only. Include duplicate requests, forged authorization,
concurrent debit, DB disconnect and collector outage locally; never target a
public endpoint. Stop on leaked data, unexpected external traffic or resource
budget breach; preserve sanitized evidence and notify the responsible reviewer.
No DDoS tests, framework installation, online server or provider configuration is
authorized by this plan. PERF-G0 through PERF-G5 remain separate future gates;
this spike cannot certify 500/1,000 CCU. Clean disposable lab data after approved
retention; restore verified snapshots for migration experiments. No production
state is changed. Document-only rollback is Git revert.
