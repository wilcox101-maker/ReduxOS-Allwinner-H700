#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Cross-compile redux-osk-pointer (the gamepad->pointer bridge for the fly-out OSK) for aarch64.
# The binary is NOT committed (no binaries in the repo); it is injected into the image at build time
# via sudo OSK_POINTER=<path> image/build-image.sh ...  usage: tools/build-osk-pointer.sh [OUTDIR]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$PWD/out-osk}; mkdir -p "$OUT"; OUT=$(readlink -f "$OUT")
TRIPLE=aarch64-linux-gnu
command -v $TRIPLE-gcc >/dev/null || { echo "missing: $TRIPLE-gcc" >&2; exit 2; }
$TRIPLE-gcc -O2 -static -Wall -Wextra -o "$OUT/redux-osk-pointer" "$HERE/redux-osk-pointer.c"
$TRIPLE-strip "$OUT/redux-osk-pointer"
file "$OUT/redux-osk-pointer" | grep -c 'ARM aarch64' >/dev/null && echo "built $OUT/redux-osk-pointer"
sha256sum "$OUT/redux-osk-pointer" | tee "$OUT/redux-osk-pointer.sha256"
