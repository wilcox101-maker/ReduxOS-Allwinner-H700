#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# setup-build-host.sh — install what the ReduxOS build needs on an Ubuntu 24.04 x86_64 host (CI runner or a
# desk machine): cross toolchain, image tools, QEMU, the arm64 multiarch -dev packages that
# tools/build-retroarch.sh and the GLES cores link against, and the aarch64 binfmt handler mmdebstrap uses.
# Changes the HOST's apt configuration (adds arm64 from ports.ubuntu.com, pins the default sources to the
# host architecture). Touches no block device. usage: sudo tools/setup-build-host.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (apt)" >&2; exit 1; }
[ "$(dpkg --print-architecture)" = amd64 ] || { echo "expects an amd64 Ubuntu 24.04 host" >&2; exit 2; }
. /etc/os-release; [ "${VERSION_CODENAME:-}" = noble ] || { echo "expects Ubuntu 24.04 (noble)" >&2; exit 2; }
export DEBIAN_FRONTEND=noninteractive

# arm64 multiarch: the default (amd64) mirrors don't carry arm64, so restrict them and add ports.ubuntu.com
dpkg --add-architecture arm64
for f in /etc/apt/sources.list.d/*.sources; do
	[ -f "$f" ] || continue
	case $f in */reduxos-arm64-ports.sources) continue ;; esac
	grep -q '^Architectures:' "$f" || sed -i '/^Types:/a Architectures: amd64' "$f"
done
# one-line .list sources (the main list and third-party repos on CI runners): amd64 only, unless they say
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
	[ -f "$f" ] || continue
	sed -i -E -e '/^deb(-src)? \[[^]]*arch=/b' -e 's/^(deb(-src)?) \[/\1 [arch=amd64 /' \
		-e 's/^(deb(-src)?) ([a-z]+:)/\1 [arch=amd64] \3/' "$f"
done
cat > /etc/apt/sources.list.d/reduxos-arm64-ports.sources <<'EOF'
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: noble noble-updates noble-security
Components: main universe
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	build-essential gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu cmake make git \
	pkgconf file curl ca-certificates unzip zstd python3 dpkg-dev \
	mmdebstrap arch-test genimage dosfstools mtools e2fsprogs fdisk \
	qemu-user-static binfmt-support qemu-system-arm
apt-get install -y -qq --no-install-recommends \
	libdrm-dev:arm64 libgbm-dev:arm64 libegl-dev:arm64 libgles-dev:arm64 libudev-dev:arm64 libasound2-dev:arm64 \
	libfreetype-dev:arm64 zlib1g-dev:arm64 liblzma-dev:arm64 libavcodec-dev:arm64 libavformat-dev:arm64 \
	libavutil-dev:arm64 libswscale-dev:arm64 libswresample-dev:arm64

# mmdebstrap runs arm64 binaries through binfmt; register it if the package didn't (containers, CI)
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	mountpoint -q /proc/sys/fs/binfmt_misc || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
	cat /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register
fi
arch-test arm64
echo "build host ready"
