#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# build-libretro-cores.sh — cross-build the ReduxOS source-built libretro cores for aarch64 (Cortex-A53, H700).
# Reads tools/cores.tsv: every core is pinned to a full upstream commit SHA, and the fetched tree is checked
# against it. The resulting .so files are NOT committed (no binaries in the repo, AGENTS.md); inject them at
# image build with
#   sudo CORES_DIR=<OUTDIR> image/build-image.sh ...
#
# usage: tools/build-libretro-cores.sh [-o OUTDIR] [-w WORKDIR] [-j N] [--include-nc] [core ...]
#   no core names = every public core in cores.tsv. Cores with a non-commercial ("nc") licence are skipped
#   unless --include-nc is given (private builds only; such an image is not a publishable ReduxOS release).  A core whose .so already sits in OUTDIR at the pinned
#   commit (OUTDIR/<core>.pin) is skipped, so an interrupted marathon resumes where it stopped.
#   One failing core does not stop the others; the summary (OUTDIR/BUILD-SUMMARY.tsv) lists each result
#   and the script exits 1 if any core failed.
#
# Host (Ubuntu 24.04 x86_64): gcc/g++-aarch64-linux-gnu, make, cmake, git, file; for the GLES cores
# (mupen64plus_next, flycast, ppsspp) also multiarch libgles-dev:arm64 libegl-dev:arm64 zlib1g-dev:arm64.
# Desk build only: nothing here proves a core runs (or runs at full speed) on the A53 — that needs hardware.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TSV=$HERE/cores.tsv
OUT=$PWD/out-cores; WORK=$PWD/.work/cores; JOBS=$(nproc); NC=0
rest=()
for a in "$@"; do [ "$a" = --include-nc ] && NC=1 || rest+=("$a"); done
set -- "${rest[@]+"${rest[@]}"}"
while getopts "o:w:j:" o; do case $o in o) OUT=$OPTARG;; w) WORK=$OPTARG;; j) JOBS=$OPTARG;;
  *) sed -n 2,16p "$0"; exit 2;; esac; done; shift $((OPTIND-1))
mkdir -p "$OUT" "$WORK/logs"; OUT=$(readlink -f "$OUT"); WORK=$(readlink -f "$WORK")
T=aarch64-linux-gnu
for t in $T-gcc $T-g++ $T-strip $T-nm $T-readelf git make cmake file; do
  command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 2; }; done

# cmake cross toolchain file (shared by the cmake cores)
TC=$WORK/aarch64-toolchain.cmake
cat > "$TC" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER $T-gcc)
set(CMAKE_CXX_COMPILER $T-g++)
set(CMAKE_FIND_ROOT_PATH /usr/$T /usr/lib/$T)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_LIBRARY_ARCHITECTURE $T)
EOF
export PKG_CONFIG_LIBDIR=/usr/lib/$T/pkgconfig:/usr/share/pkgconfig

fetch() { # url pin dir — shallow fetch of exactly the pinned commit, plus submodules
  local url=$1 pin=$2 d=$3
  if [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" != "$pin" ]; then
    rm -rf "$d"; git init -q "$d" && git -C "$d" remote add origin "$url" &&
    git -C "$d" fetch -q --depth 1 origin "$pin" && git -C "$d" checkout -q FETCH_HEAD || return 1
  fi
  [ "$(git -C "$d" rev-parse HEAD)" = "$pin" ] || { echo "not at pinned commit $pin" >&2; return 1; }
  # Some servers refuse shallow submodule SHAs; some cores carry a stale nested submodule they never build
  # (mupen64plus-nx: paraLLEl's gnulib). A missing submodule that matters fails the build, not the fetch.
  git -C "$d" submodule update -q --init --recursive --depth 1 2>/dev/null ||
    git -C "$d" submodule update -q --init --recursive ||
    echo "warning: some submodules did not fetch; continuing" >&2
}

check_so() { # file -> 0 if an aarch64 shared object exporting the libretro API
  [ -f "$1" ] || { echo "no .so produced"; return 1; }
  [ "$(file -b "$1" | grep -c 'ARM aarch64')" -ge 1 ] || { echo "not aarch64: $(file -b "$1")"; return 1; }
  [ "$($T-nm -D "$1" | grep -c '\<retro_api_version\>')" -ge 1 ] || { echo "no libretro API"; return 1; }
  # GL entry points left undefined with no GL library in NEEDED fail to dlopen (ppsspp, found by the QEMU
  # smoke check): such a core must link libGLESv2 itself.
  if [ "$($T-nm -D --undefined-only "$1" | grep -c ' gl[A-Z]')" -gt 0 ] &&
     [ "$($T-readelf -d "$1" | grep -c 'NEEDED.*lib\(GLESv2\|GL\)\.so')" -eq 0 ]; then
    echo "undefined gl* symbols but no libGLESv2/libGL in NEEDED"; return 1; fi
}

SUMMARY=$OUT/BUILD-SUMMARY.tsv
[ -f "$SUMMARY" ] || printf "#core\tresult\tpin\tsize\tsha256\tlicence\n" > "$SUMMARY"
fail=0
while IFS=$'\t' read -r core url pin kind dir mk args so lic _systems; do
  [[ -z "$core" || "$core" == \#* ]] && continue
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qxF "$core"; then continue; fi
  case "$lic" in nc*) if [ "$NC" = 0 ]; then echo "- $core: skipped (non-commercial licence: $lic; --include-nc for a private build)"; continue; fi ;; esac
  dst=$OUT/${core}_libretro.so; log=$WORK/logs/$core.log
  if [ -f "$dst" ] && [ "$(cat "$OUT/$core.pin" 2>/dev/null)" = "$pin" ]; then echo "= $core (already built at ${pin:0:12})"; continue; fi
  echo "> $core (${pin:0:12}) ..."; start=$(date +%s)
  src=$WORK/src/$(basename "$url")
  (
    set -e
    fetch "$url" "$pin" "$src"
    # shellcheck disable=SC2086
    if [ "$kind" = cmake ]; then
      b=$src/build-aarch64; rm -rf "$b"
      cmake -S "$src/$dir" -B "$b" -DCMAKE_TOOLCHAIN_FILE="$TC" $args
      cmake --build "$b" -j"$JOBS"
    else
      make -C "$src/$dir" -f "$mk" $args clean >/dev/null 2>&1 || true   # vice: one tree, two EMUTYPEs
      make -C "$src/$dir" -f "$mk" $args CC=$T-gcc CXX=$T-g++ AR=$T-ar AS=$T-as\
        STRIP=$T-strip -j"$JOBS"
    fi
  ) < /dev/null > "$log" 2>&1   # stdin closed: make/git must not eat the cores.tsv lines
  rc=$?
  built=$src/$so; [ "$kind" = cmake ] && built=$src/build-aarch64/$so
  [ -f "$built" ] || built=$(find "$src" -name "$(basename "$so")" -newer "$TC" 2>/dev/null | head -1)
  mins=$(( ($(date +%s)-start)/60 ))
  sed -i "/^${core}\t/d" "$SUMMARY"
  if [ $rc -eq 0 ] && why=$(check_so "$built"); then
    $T-strip --strip-unneeded "$built" -o "$dst"
    echo "$pin" > "$OUT/$core.pin"
    mkdir -p "$OUT/licences/$core"
    find "$src" -maxdepth 2 -iregex '.*/\(license\|licence\|copying\|copyright\)[^/]*' -type f \
      -exec cp {} "$OUT/licences/$core/" \; 2>/dev/null
    printf "%s\t%s\n" "$url" "$pin" > "$OUT/licences/$core/SOURCE"
    sz=$(stat -c %s "$dst"); sum=$(sha256sum "$dst" | cut -d' ' -f1)
    printf "%s\tok\t%s\t%s\t%s\t%s\n" "$core" "$pin" "$sz" "$sum" "$lic" >> "$SUMMARY"
    echo "  ok $core: $((sz/1024)) KiB, ${mins} min"
  else
    [ $rc -ne 0 ] && why="build failed (rc=$rc), see $log"
    printf "%s\tFAIL\t%s\t-\t-\t%s\n" "$core" "$pin" "$lic" >> "$SUMMARY"
    echo "  FAIL $core: $why (${mins} min)"; tail -5 "$log" | sed 's/^/    /'; fail=1
  fi
done < "$TSV"
( cd "$OUT" && sha256sum ./*_libretro.so > SHA256SUMS 2>/dev/null )
exit $fail
