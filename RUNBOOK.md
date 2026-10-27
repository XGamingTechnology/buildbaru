# Initial incident response checklist (draft)

1. Capture timeline; distinguish network PPS/BPS/packet loss from join failures, FXServer hitches and DB latency.
2. If upstream traffic is saturated, contact approved mitigation provider; do not improvise changes to a public origin.
3. Apply only documented, pre-tested, reversible admission rules and monitor false rejection of CGNAT users.
4. If a gameplay exploit is isolated, consider disabling the affected resource through approved change control rather than mass-kicking.
5. Keep evidence/audit logs, communicate status and test recovery across representative ISP routes.
6. Reconcile database and carry out post-incident review with ownership and follow-up actions.

No automatic AI network actions are authorized.
