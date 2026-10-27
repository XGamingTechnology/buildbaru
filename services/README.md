# Future services (NOT implemented)

- `sentinel-ingest`: Rust collector and normalization with backpressure.
- `sentinel-policy`: Rust versioned rules, constrained mitigation approval, expiry and rollback.
- `sentinel-api`: Rust internal API for SOC read access / approval workflows.
- `ai-evaluation`: offline labeled evaluation and shadow mode, never control of production firewall.

Create service-specific manifests and tests only after API/contracts ADRs are approved.
