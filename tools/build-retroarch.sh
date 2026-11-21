#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# build-retroarch.sh — cross-build upstream RetroArch for ReduxOS and package it as
# reduxos-retroarch_<ver>_arm64.deb.
#
# Why: noble's retroarch (1.18, universe) is built for desktops: it links Qt5, X11, Wayland, PulseAudio and
# JACK, and hard-depends on retroarch-assets (~440 MB of fonts). ReduxOS only uses KMS/EGL/GLES + udev + ALSA
# with the rgui menu. This build keeps exactly that (plus FFmpeg for the built-in media player, FreeType, zlib,
# networking/netplay) and drops the rest. Core downloads from the buildbot are disabled (ReduxOS ships its
# own pinned cores; buildbot cores are unverified binaries).
#
# The .deb is NOT committed (no binaries in the repo); inject it with
#   sudo RETROARCH_DEB=<OUTDIR>/reduxos-retroarch_<ver>-1reduxos1_arm64.deb image/build-image.sh ...
# It Provides retroarch and libretro-frontend, so noble's libretro-* core packages still install.
#
# usage: tools/build-retroarch.sh [OUTDIR] [WORKDIR]      (defaults ./out-retroarch, ./.work/retroarch)
# Host (Ubuntu 24.04 x86_64): gcc/g++-aarch64-linux-gnu, make, git, pkgconf, dpkg-dev, and multiarch
#   libdrm-dev libgbm-dev libegl-dev libgles-dev libudev-dev libasound2-dev libfreetype-dev zlib1g-dev
#   libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev liblzma-dev   (all :arm64)
# Pin: tag v1.22.2 = commit below (record changes in PROVENANCE.md). The fetched tree is checked against the
# pin before building. Desk build: nothing here proves it renders on the Mali-G31 — that needs the device.
set -euo pipefail
VER=1.22.2
PIN=69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576      # libretro/RetroArch tag v1.22.2
OUT=$(readlink -f "${1:-$PWD/out-retroarch}"); WORK=$(readlink -f "${2:-$PWD/.work/retroarch}")
T=aarch64-linux-gnu
mkdir -p "$OUT" "$WORK"
for t in $T-gcc $T-g++ $T-strip $T-readelf git make pkgconf file dpkg-deb dpkg-query; do
  command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 2; }; done

S=$WORK/src
if [ "$(git -C "$S" rev-parse HEAD 2>/dev/null)" != "$PIN" ]; then
  rm -rf "$S"; git init -q "$S"
  git -C "$S" fetch -q --depth 1 https://github.com/libretro/RetroArch "$PIN"
  git -C "$S" checkout -q FETCH_HEAD
fi
[ "$(git -C "$S" rev-parse HEAD)" = "$PIN" ] || { echo "source is not at the pinned commit $PIN" >&2; exit 1; }

cd "$S"
git clean -qfdx
export PKG_CONFIG_LIBDIR=/usr/lib/$T/pkgconfig:/usr/share/pkgconfig PKG_CONF_PATH=pkgconf
export CROSS_COMPILE=$T- CC=$T-gcc CXX=$T-g++
./configure --host=$T --prefix=/usr \
  --enable-kms --enable-egl --enable-opengles --enable-opengles3 --enable-opengles3_1 \
  --enable-udev --enable-alsa --enable-ffmpeg --enable-freetype --enable-zlib --enable-threads \
  --disable-opengl1 --disable-x11 --disable-xrandr --disable-xinerama --disable-wayland --disable-qt \
  --disable-pulse --disable-jack --disable-oss --disable-sdl --disable-sdl2 --disable-vulkan \
  --disable-discord --disable-update_cores --disable-videocore --disable-mali_fbdev \
  > "$WORK/configure.log" 2>&1 || { tail -30 "$WORK/configure.log"; exit 1; }
make -j"$(nproc)" > "$WORK/make.log" 2>&1 || { tail -30 "$WORK/make.log"; exit 1; }

B=$S/retroarch
[ "$(file -b "$B" | grep -c 'ARM aarch64')" -ge 1 ] || { echo "not an aarch64 binary" >&2; exit 1; }
# the point of this build: no desktop stacks may be linked
if $T-readelf -d "$B" | grep NEEDED | grep -E 'Qt[56]|libX11|libxcb|libwayland|libpulse|libjack|libSDL|libvulkan'; then
  echo "unexpected desktop library linked (above)" >&2; exit 1; fi

# ---- package: binary + copyright, Depends derived from the binary's NEEDED sonames ----
P=$WORK/pkg; rm -rf "$P"; mkdir -p "$P/DEBIAN" "$P/usr/bin" "$P/usr/share/doc/reduxos-retroarch"
$T-strip --strip-unneeded -o "$P/usr/bin/retroarch" "$B"
cp COPYING "$P/usr/share/doc/reduxos-retroarch/COPYING"
printf '%s\n' "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/" \
  "Upstream-Name: RetroArch" "Source: https://github.com/libretro/RetroArch (tag v$VER, $PIN)" "" \
  "Files: *" "Copyright: The RetroArch team" "License: GPL-3.0-or-later" \
  " Full text: /usr/share/doc/reduxos-retroarch/COPYING; on Debian systems also /usr/share/common-licenses/GPL-3." \
  "" "Comment: built for ReduxOS by tools/build-retroarch.sh; configure flags in that script." \
  > "$P/usr/share/doc/reduxos-retroarch/copyright"
deps=$($T-readelf -d "$B" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | while read -r so; do
  f=$(readlink -f "/usr/lib/$T/$so" 2>/dev/null || true)
  [ -n "$f" ] && [ -e "$f" ] || f=/lib/$T/$so
  dpkg-query -S "$f" 2>/dev/null | head -1 | cut -d: -f1; done | sort -u | paste -sd, | sed 's/,/, /g')
[ -n "$deps" ] || { echo "could not resolve library packages" >&2; exit 1; }
cat > "$P/DEBIAN/control" <<EOF
Package: reduxos-retroarch
Version: $VER-1reduxos1
Architecture: arm64
Maintainer: ReduxOS <noreply@example.invalid>
Depends: $deps, libretro-core-info, fonts-dejavu-core
Provides: retroarch (= $VER), libretro-frontend
Conflicts: retroarch
Replaces: retroarch
Section: games
Priority: optional
Homepage: https://www.retroarch.com/
Description: RetroArch $VER for ReduxOS (KMS/EGL/GLES, udev, ALSA, rgui)
 Cross-built from upstream tag v$VER without Qt, X11, Wayland, PulseAudio, JACK or SDL,
 and without buildbot core downloads. Built by tools/build-retroarch.sh (ReduxOS).
EOF
DEB=$OUT/reduxos-retroarch_${VER}-1reduxos1_arm64.deb
dpkg-deb --root-owner-group -Zxz --build "$P" "$DEB" >/dev/null
sha256sum "$DEB" | tee "$DEB.sha256"
echo "Depends: $deps"
