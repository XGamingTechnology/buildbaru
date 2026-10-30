# Tests

All tests use local, synthetic data only.

```bash
python3 -m pip install -r tests/requirements.txt
python3 -m unittest discover -s tests -v
```

| File | Covers | Needs |
|---|---|---|
| `test_contracts.py` | Six v1 schemas, valid examples, privacy and negative fixtures | — |
| `test_lua_units.py` | Telemetry queue bounds, envelope privacy guard, economy request validation (Lua 5.4 via lupa) | — |
| `test_admission.py` | Admission modes, CGNAT fairness, cooldown expiry, queue order/capacity/reservations/timeout, pseudonym refs, schema fit | — |
| `test_db_ops.py` | Operator roles, MFA, two-person rule, no ban/firewall kinds, TTL bounds, evidence, revoke/expiry, trigger guards, audit hash chain, concurrent appends, down migration | Disposable MariaDB via `SENTINEL_TEST_DB_*`, otherwise skipped |
| `test_db_ledger.py` | Ledger atomicity, idempotent replay, concurrent debit, duplicate submission, deadlock ordering, lock timeout, append-only, reconciliation, down migration | Disposable MariaDB via `SENTINEL_TEST_DB_*`, otherwise skipped |

`test_db_ledger.py` and `test_db_ops.py` drop and recreate their tables. Never
point them at a shared or production database.

Not yet covered: running resources inside FXServer, oxmysql result shapes,
permissions, inventory, FXServer deferrals, restore drills and any
performance gate. No test here demonstrates real FiveM behaviour or CCU.
