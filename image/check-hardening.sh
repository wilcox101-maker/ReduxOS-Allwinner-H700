#!/usr/bin/env bash
# check-hardening.sh — assert the built rootfs meets the ReduxOS security baseline. Intended checks:
#   - no shipped root password; root login key-only/opt-in; per-unit host-key + machine-id regen on first boot
#   - firewall enabled with an explicit allow policy (not installed-but-inactive)
#   - no world-writable root-owned code paths; no code executed as root from the card
#   - no desktop stacks (Qt/X11/Wayland/Pulse/JACK) linked into the frontend
#   - persistent journal enabled
# Usage: ./image/check-hardening.sh <rootfs-or-out-dir>
#
# STATUS: stub. Brought in alongside the build pipeline — see docs/status.md / SECURITY.md.
set -uo pipefail

root="${1:-}"
echo "check-hardening.sh is not yet implemented." >&2
[ -n "$root" ] && echo "would check: $root" >&2
echo "Baseline it will enforce is in SECURITY.md / docs/risks-eliminated.md." >&2
exit 1
