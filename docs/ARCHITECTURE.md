# Architecture boundaries (proposal)

```text
Indonesian FiveM Clients
        |
[Provider-level protected edge, TCP/UDP + HTTPS]
        |
   [FXServer / OneSync] -----> [MariaDB: persistent records + audit ledger]
        |                            |
  Lua/TS server resources            +----> [Encrypted off-site backups]
        |
   [Non-blocking telemetry events]
        |
   [Sentinel ingestion / normalization in Rust] ---> [Rules / incident store]
                                                   |
                                            [SOC dashboard / operator]
                                                   |
                                          [Approved, time-limited actions]

[Redis] ephemeral coordination only; never the sole source of money balances.
[AI analyst] evidence-grounded read-only incident summarization / shadow evaluation only.
```

## Design principles
- Game ticks do not make synchronous network roundtrips to Sentinel.
- AI/collector failure must not terminate existing gameplay sessions.
- If database consistency is at risk, block financial mutations rather than assume commit success.
- Every security action needs evidence, reason, authorization, expiry and rollback.
- Filter and pseudonymize player-related telemetry and set retention after privacy review.
- This diagram is logical; no vendor, routable address or hardware is selected.
