# Admission and join queue (draft)

PRD IDs (provisional): NET-005, NET-006, NET-007, SEC-004, NFR-03.
Resource: `fivem/resources/[sentinel]/sentinel_admission`. Logic lives in
`shared/admission.lua` (pure, unit tested); `server/main.lua` wires it to
`playerConnecting` deferrals. Nothing here has run inside FXServer yet.

## Flow

```text
playerConnecting
  └─ defer ─ evaluate(identity, source)
        ├─ enforce mode and would ≠ accepted → done(message)   [deferred/rejected]
        └─ accepted → capacity queue
              ├─ queue full → done(queue_full)
              ├─ head of queue and connected + reserved < sv_maxclients → admit
              ├─ waited > queue timeout → done(timeout)
              └─ client left → leave queue
  any error inside admission → admit (fail-open, NET-007)
```

## Rules

| Signal | Observe mode | Enforce mode |
|---|---|---|
| No `license` identifier | admit, record `would=rejected` | reject with login hint |
| More than `rate_max` attempts per identity per window | admit, record `would=deferred` | refuse for `cooldown_s` seconds, then normal |
| Many sessions from one network source | record `shared_source_count` only | same; **never** a reason to refuse (CGNAT) |
| Server full | queue (FIFO; reconnect keeps place) | same |
| Admission error | admit | admit |

There are no permanent bans, no IP or ASN blocks, and no firewall actions here.
Sentinel or AI scores are not yet inputs (D-05).

## Privacy
Raw `license` and endpoint values exist only in memory. They map to random
refs that are forgotten after `refTtlS` of inactivity, and are never logged or
emitted. Telemetry carries only refs and counts (`connection_attempt` v1).

## Configuration (`server.cfg`)

| Convar | Default |
|---|---|
| `sentinel_admission_mode` | `observe` |
| `sentinel_admission_queue_capacity` | 200 |
| `sentinel_admission_queue_timeout_s` | 900 |
| `sentinel_admission_rate_window_s` / `_rate_max` | 60 / 6 |
| `sentinel_admission_cooldown_s` | 30 |

## Moving to enforce (needs owner approval)
1. Run observe mode on staging and closed alpha. Review `would_outcome` rates,
   especially false `rate_limited` from shared networks.
2. Record the evidence (dates, sample size, false-positive review) in the PR or issue.
3. Switch the convar to `enforce`. Rollback is setting it back to `observe`,
   which needs no restart of other resources.

## Known gaps
- FXServer behaviour of deferrals, `GetPlayerEndpoint` during connect and the
  temporary vs. final server id is unverified.
- Priority or whitelist queues, staff bypass and Sentinel inputs are not designed yet.
- Load behaviour of the queue at 500 CCU is unmeasured (PERF gates).
