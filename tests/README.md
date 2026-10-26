# Required tests (future)

Functional: character persistence, permissions, inventory and reconnect.
Security: forged event rejection, privilege escalation, CGNAT fairness and admission degradation.
Economy: atomic debit/credit, repeated idempotency key, concurrent spending and DB interruption.
Performance: real or otherwise clearly identified test clients, hotspot and varied ISP metrics.
Restore: offsite recovery, migration rollback and ledger reconciliation.

No tests in this repository yet demonstrate real FiveM behavior.

## Discovery static validation

Run `python3 tests/check_discovery.py` from the repository root (Python standard
library only). CI runs this check alongside the existing scaffold checks. It
checks document titles, whitespace, fence balance, relative file links and spike
matrix weight totals; it does not validate PRD completeness or runtime behavior.
