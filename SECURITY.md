# Security Policy

ReduxOS is built ground-up from Ubuntu 24.04 and upstream source. It does not inherit the stock firmware's
defaults and is hardened from the start (see [`docs/risks-eliminated.md`](docs/risks-eliminated.md)).

## Baseline guarantees (design intent)
- **No shared factory credentials.** SSH host keys and `/etc/machine-id` are generated **per unit on first
  boot**; there is no shipped root password or key, and remote root password login is off by default.
- **Firewall enabled** with an explicit allow policy (not installed-but-inactive).
- **No world-writable root-owned code paths; no code executed as root from the removable card.**
- **No device-lock / anti-tamper mechanism** and no dependency on one.
- **No telemetry.** Nothing contacts the network unprompted; any networked app is user-launched and documented.

## Reporting a vulnerability
Please open a private advisory (GitHub Security Advisories) or contact the maintainer rather than filing a
public issue for anything exploitable. We practice coordinated disclosure.

## Note on stock-firmware analysis
Any analysis of the *stock* vendor firmware (which motivated several of these defaults) is kept in a separate
private record and is deliberately **not** in this repo; this repo documents only what ReduxOS itself does.
