# Tests

All tests use local, synthetic data only.

```bash
python3 -m pip install -r tests/requirements.txt
python3 -m unittest discover -s tests -v
```

| File | Covers | Needs |
|---|---|---|
| `test_static.py` | All Lua files compile (Lua 5.4), shell scripts parse, selftest not in the production example | — |
| `test_contracts.py` | Six v1 schemas, valid examples, privacy and negative fixtures | — |
| `test_lua_units.py` | Telemetry queue bounds, envelope privacy guard, economy request validation (Lua 5.4 via lupa) | — |
| `test_admission.py` | Admission modes, CGNAT fairness, cooldown expiry, queue order/capacity/reservations/timeout, pseudonym refs, schema fit | — |
| `test_db_ops.py` | Operator roles, MFA, two-person rule, no ban/firewall kinds, TTL bounds, evidence, revoke/expiry, trigger guards, audit hash chain, concurrent appends, down migration | Disposable MariaDB via `SENTINEL_TEST_DB_*`, otherwise skipped |
| `test_qbox_logic.py` | `rp_qbx_bridge` money guard and keys, `rp_banking` validation, distance check, rate limiter | — |
| `test_db_accounts.py` | `econ_open_account` idempotency, case sensitivity, refusals | Disposable MariaDB |
| `test_db_ledger.py` | Ledger atomicity, idempotent replay, concurrent debit, duplicate submission, deadlock ordering, lock timeout, append-only, reconciliation, down migration | Disposable MariaDB via `SENTINEL_TEST_DB_*`, otherwise skipped |

`test_db_ledger.py` and `test_db_ops.py` drop and recreate their tables. Never
point them at a shared or production database.

Not yet covered (see `deploy/staging` for the FXServer selftest): running resources inside FXServer, oxmysql result shapes,
permissions, inventory, FXServer deferrals, restore drills and any
performance gate. No test here demonstrates real FiveM behaviour or CCU.

## Discovery static validation

Run `python3 tests/check_discovery.py` from the repository root (Python standard
library only). CI runs this check alongside the existing scaffold checks. It
checks document titles, whitespace, fence balance, relative file links and spike
matrix weight totals; it does not validate PRD completeness or runtime behavior.
