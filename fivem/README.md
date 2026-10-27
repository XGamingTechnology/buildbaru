# FiveM resources (NOT implemented)

Keep gameplay resources server-authoritative and isolated by domain. No downloaded third-party RP core is included. Do not deploy example config without an approved game DDoS protected endpoint, origin policy, reviewed resources, and distinct secret storage.

Intended layout: `resources/[rp]/`, `resources/[sentinel]/` and non-secret `config/`. Empty directories are not retained by Git; add them alongside approved resources.
