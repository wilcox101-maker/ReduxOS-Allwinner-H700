# AI collaborators — ReduxOS — Allwinner H700

Dale owns the project. Authoritative rules are in [`README.md`](README.md) + [`CONTRIBUTING.md`](CONTRIBUTING.md).

- Work **desk-only** until a device is validated; one topic per branch → PR into protected `main`; CI stays green.
- **Never commit** binaries, blobs, BIOS, ROMs, stock-derived files, or secrets. Everything builds from source.
- **Never write to a card or a device** from a tool; card-writing is a manual, deliberate step.
- Security defaults (per-unit credentials, firewall-on, least privilege) are not to be regressed.
- Every claim states whether it was checked on hardware (`[V]`) or is desk-only.
- **Dale decides:** licence, rule-file changes, device writes, security calls, and anything irreversible or unclear.
