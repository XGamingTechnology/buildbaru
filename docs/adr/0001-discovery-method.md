# ADR 0001 — Evidence-first legacy and framework discovery

Status: DRAFT; not accepted. Date: 2026-10-26.
Decision IDs: D-01, D-02. Tracking issue: TBD.
Decision owner: Architecture lead TBD; approver: Product owner TBD.

## Context

Only the [PRD summary](../PRD_CONTEXT.md) is available; historical code, asset
rights, infrastructure, budget and people are unknown. Requirement mappings
G-04, RP-004, NET-007, SEC-001/002/014, SEC-013 and PERF-G0 require full-PRD
confirmation. Framework preference without reproducible evidence would conceal
migration, licensing, security and economy risks.

## Proposed decision

Use the [D-01 audit template](../discovery/LEGACY_AUDIT.md),
[D-02 spike plan](../discovery/TECHNICAL_SPIKE.md) and
[kickoff gates](../discovery/KICKOFF_GATES.md). Compare pinned Qbox,
legacy and custom candidates with fixed workloads, mandatory safety gates and
explicit scoring. No framework winner, reuse decision or runtime deployment is
selected by this ADR. D-01 and D-02 remain open.

## Alternatives and consequences

Immediate rewrite avoids some legacy coupling but has unmeasured effort and parity
risk. Immediate reuse could preserve behavior but lacks provenance/security evidence.
Immediate Qbox adoption has untested compatibility and migration cost. A bounded
comparison costs discovery effort but exposes these unknowns before commitment.
Unavailable candidates must be identified rather than assigned fabricated scores.

## Verification, failure and rollback

Document checks verify local links, formatting and matrix weights, not runtime
behavior. Review licensing, authorization, duplicate economy mutations, DB failure
and telemetry outage evidence before accepting a candidate. Missing or conflicting
evidence keeps the decision open. No production changes occur. Revert this slice
to withdraw the proposal; supersede this ADR after reviewed results rather than
rewriting its decision history. Any later migration needs a separately tested rollback.
