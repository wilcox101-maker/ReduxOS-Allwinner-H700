#!/usr/bin/env bash
# smoke-test.sh — boot a built ReduxOS image under QEMU (aarch64, cortex-a53) and run checks:
#   image boots; frontend (RetroArch KMS/GLES) present; no desktop stacks; hardening checks pass.
# Usage: ./image/qemu/smoke-test.sh <path-to-image.img>
#
# STATUS: stub. Brought in alongside the build pipeline — see docs/status.md / docs/build.md.
set -uo pipefail

img="${1:-}"
echo "smoke-test.sh is not yet implemented (QEMU boot + checks)." >&2
[ -n "$img" ] && echo "would test image: $img" >&2
echo "See docs/status.md for the pipeline plan." >&2
exit 1
