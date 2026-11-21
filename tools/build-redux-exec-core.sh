#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Cross-build redux_exec_libretro.so (tools/redux-exec-core.c, the ReduxOS launcher core: runs PortMaster
# ports and native .sh apps from RetroArch playlists). libretro.h (MIT) is fetched from libretro-common at a
# pinned commit, not committed. The .so is NOT committed; it goes into the image's cores via
#   tools/build-redux-exec-core.sh <CORES_OUTDIR>   then   sudo CORES_DIR=<CORES_OUTDIR> image/build-image.sh ...
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(readlink -f "${1:-$PWD/out-cores}"); mkdir -p "$OUT"
PIN=52781c4a8b5aae19d858f4a2326c8f8308c70f54   # libretro/libretro-common (master at pin time; untagged)
T=aarch64-linux-gnu
command -v $T-gcc >/dev/null || { echo "missing: $T-gcc" >&2; exit 2; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git init -q "$W/lc" && git -C "$W/lc" fetch -q --depth 1 https://github.com/libretro/libretro-common "$PIN" &&
  git -C "$W/lc" checkout -q FETCH_HEAD
$T-gcc -O2 -fPIC -shared -Wall -Wextra -Werror -I"$W/lc/include" -fvisibility=default \
  -Wl,--no-undefined -o "$OUT/redux_exec_libretro.so" "$HERE/redux-exec-core.c"
$T-strip --strip-unneeded "$OUT/redux_exec_libretro.so"
[ "$(file -b "$OUT/redux_exec_libretro.so" | grep -c 'ARM aarch64')" -ge 1 ]
[ "$($T-nm -D "$OUT/redux_exec_libretro.so" | grep -c '\<retro_load_game\>')" -ge 1 ]
echo "$PIN" > "$OUT/redux_exec.pin"
sha256sum "$OUT/redux_exec_libretro.so" | tee "$OUT/redux_exec_libretro.so.sha256"
