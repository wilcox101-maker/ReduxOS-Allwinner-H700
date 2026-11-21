#!/usr/bin/env bash
# check-licences.sh — verify every component in the built image is accounted for in PROVENANCE.md
# with a licence, and that no stock/vendor/BIOS/ROM material is present. Intended checks:
#   - each installed package / source-built component maps to a PROVENANCE.md row
#   - no file matches the blocklist (vendor firmware, console BIOS, known ROM signatures)
# Usage: ./tools/check-licences.sh <rootfs-or-out-dir>
#
# STATUS: stub. Brought in alongside the build pipeline — see docs/status.md / PROVENANCE.md.
set -uo pipefail

root="${1:-}"
echo "check-licences.sh is not yet implemented." >&2
[ -n "$root" ] && echo "would check: $root against PROVENANCE.md" >&2
exit 1
