#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# build-image.sh — assemble a ReduxOS card image: Ubuntu 24.04 (noble) arm64 packages from
# image/packages.txt, the ReduxOS config in image/rootfs/, a kernel package, and (for a device image) an
# H700 u-boot for the unit's DRAM type.
#
#   mmdebstrap (rootfs from packages.txt) -> customize (rootfs tree, users, injected components,
#   extlinux via u-boot-menu) -> genimage (MBR: u-boot @ 8 KiB, FAT32 /boot @ 16 MiB, ext4 root)
#
# Writes only under $OUT. It NEVER touches a block device: writing the image to a card is a separate,
# deliberate, manual step (docs/build.md).
#
# usage: sudo [ENV...] image/build-image.sh [--ci] [--dram lpddr4|lpddr3]
#   --ci             CI/QEMU profile: KERNEL=ubuntu, no u-boot. Injected components still apply if set.
#   --dram TYPE      the DRAM type the image is for; must match UBOOT_BIN (LPDDR3 settings put 1.2 V on
#                    1.1 V LPDDR4, so a mismatch is an error, never a warning).
# Kernel (one of):
#   KERNEL_DEB=<.deb>  the ReduxOS H700 kernel package (built outside this repo for now; see docs/status.md)
#   KERNEL=ubuntu      Ubuntu's generic arm64 kernel + initramfs: QEMU testing ONLY, it cannot boot an H700
# Bootloader (device images only):
#   UBOOT_BIN=u-boot-<device>-<lpddr4|lpddr3>-<ver>.bin  with its -NOTICES.txt (and .config) beside it.
#   Without it the image has NO bootloader and can only be booted in QEMU (name ends in -qemu).
# Injected at build, never committed (each from its tools/ script):
#   RETROARCH_DEB=<deb>   lean upstream RetroArch, KMS/GLES only     (tools/build-retroarch.sh)
#   CORES_DIR=<dir>       source-built *_libretro.so + licences      (tools/build-libretro-cores.sh,
#                                                                     tools/build-redux-exec-core.sh)
#   OSK_POINTER=<bin>     gamepad->pointer bridge for the fly-out OSK (tools/build-osk-pointer.sh)
#   PORTMASTER_ZIP=<zip>  pinned PortMaster release                  (tools/fetch-portmaster.sh)
# Other: OUT (default ./out), DEVICE (default rg34xxsp), MIRROR, SOURCE_DATE_EPOCH, BOOT_MB.
#   ALLOW_NOBLE_RETROARCH=1  dev only: use noble's desktop-linked retroarch when RETROARCH_DEB is unset.
# Host: mmdebstrap genimage dosfstools mtools e2fsprogs fdisk dpkg-dev, and on non-arm64 hosts
#   qemu-user-static + binfmt (aarch64).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")

CI=0; DRAM=""
while [ $# -gt 0 ]; do
	case $1 in
	--ci) CI=1 ;;
	--dram) DRAM=${2:-}; shift ;;
	-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
	*) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
	esac
	shift
done
case $DRAM in ""|lpddr4|lpddr3) ;; *) echo "--dram must be lpddr4 or lpddr3" >&2; exit 2 ;; esac
[ "$CI" = 1 ] && KERNEL=${KERNEL:-ubuntu}

OUT=${OUT:-$PWD/out}; MIRROR=${MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
DEVICE=${DEVICE:-rg34xxsp}
SUITE=noble; DISK_SIG=${DISK_SIG:-0x48373030}          # "H700": fixed so PARTUUIDs are reproducible
BOOT_MB=${BOOT_MB:-256}
UBUNTU_KVER=${UBUNTU_KVER:-6.8.0-151-generic}                       # QEMU-only kernel (KERNEL=ubuntu); bump with noble-updates
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || date +%s)}
[ "$(id -u)" = 0 ] || { echo "run as root (mmdebstrap root mode, chroot, genimage)" >&2; exit 1; }
case $DEVICE in *[!a-z0-9-]*|"") echo "DEVICE must be [a-z0-9-]+" >&2; exit 2 ;; esac
for t in mmdebstrap genimage mcopy mkfs.vfat mke2fs dpkg-deb dpkg-scanpackages; do
	command -v "$t" >/dev/null || { echo "missing host tool: $t" >&2; exit 2; }
done

if [ -n "${KERNEL_DEB:-}" ]; then KMODE=deb; KERNEL_DEB=$(readlink -f "$KERNEL_DEB")
	[ -f "$KERNEL_DEB" ] || { echo "KERNEL_DEB not found" >&2; exit 2; }
elif [ "${KERNEL:-}" = ubuntu ]; then KMODE=ubuntu
else echo "set KERNEL_DEB=<ReduxOS kernel .deb>, or KERNEL=ubuntu / --ci (QEMU only)" >&2; exit 2; fi

# The u-boot binary is DRAM-specific, so the image name says which one it carries. Taken from the
# binary's file name and, when present, checked against the .config written next to it.
UBOOT_DRAM=""
if [ -n "${UBOOT_BIN:-}" ]; then
	[ "$CI" = 0 ] || { echo "--ci builds have no bootloader; unset UBOOT_BIN" >&2; exit 2; }
	UBOOT_BIN=$(readlink -f "$UBOOT_BIN")
	case "$(basename "$UBOOT_BIN")" in
	u-boot-"$DEVICE"-lpddr4-*.bin) UBOOT_DRAM=lpddr4 ;;
	u-boot-"$DEVICE"-lpddr3-*.bin) UBOOT_DRAM=lpddr3 ;;
	*) echo "UBOOT_BIN must be named u-boot-$DEVICE-<lpddr4|lpddr3>-<ver>.bin" >&2; exit 2 ;;
	esac
	UBOOT_NOTICES=$(ls "$(dirname "$UBOOT_BIN")"/u-boot-"$DEVICE"-*-NOTICES.txt 2>/dev/null | head -1 || true)
	[ -f "$UBOOT_NOTICES" ] || { echo "no u-boot-$DEVICE-*-NOTICES.txt next to $UBOOT_BIN (licence notices are required)" >&2; exit 2; }
	if [ -f "${UBOOT_BIN%.bin}.config" ] &&
	   ! grep -q "^CONFIG_SUNXI_DRAM_H616_${UBOOT_DRAM^^}=y" "${UBOOT_BIN%.bin}.config"; then
		echo "$(basename "$UBOOT_BIN"): its .config is not ${UBOOT_DRAM^^}" >&2; exit 2
	fi
	if [ -n "$DRAM" ] && [ "$DRAM" != "$UBOOT_DRAM" ]; then
		echo "--dram $DRAM but UBOOT_BIN is $UBOOT_DRAM: refusing (wrong DRAM voltage)" >&2; exit 2
	fi
elif [ -n "$DRAM" ]; then
	echo "--dram $DRAM needs UBOOT_BIN (the DRAM type lives in the bootloader)" >&2; exit 2
fi

STAMP=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d)
NAME=reduxos-$DEVICE-noble-$STAMP-$KMODE${UBOOT_DRAM:+-$UBOOT_DRAM}
[ -n "$UBOOT_DRAM" ] || NAME=$NAME-qemu
ROOT="root=PARTUUID=$(printf '%08x' $((DISK_SIG)))-02"
log() { printf '== %s\n' "$*"; }

# Injected components: fail early on a bad path rather than deep inside mmdebstrap.
for v in RETROARCH_DEB OSK_POINTER PORTMASTER_ZIP; do
	p=${!v:-}; [ -z "$p" ] || [ -f "$p" ] || { echo "$v not found: $p" >&2; exit 2; }
	[ -z "$p" ] || printf -v "$v" '%s' "$(readlink -f "$p")"
done
if [ -n "${CORES_DIR:-}" ]; then
	CORES_DIR=$(readlink -f "$CORES_DIR")
	ls "$CORES_DIR"/*_libretro.so >/dev/null 2>&1 || { echo "CORES_DIR has no *_libretro.so: $CORES_DIR" >&2; exit 2; }
fi

# A failed earlier run can leave the /boot tmpfs (and mmdebstrap mounts) behind under $OUT/rootfs.
mkdir -p "$OUT"; OUT=$(readlink -f "$OUT")
awk -v r="$OUT/rootfs/" 'index($2, r) == 1 {print $2}' /proc/mounts | sort -r | while read -r m; do umount -l "$m"; done
rm -rf "$OUT/rootfs" "$OUT/tmp" "$OUT/genimage"; mkdir -p "$OUT/rootfs" "$OUT/tmp" "$OUT/genimage"
PKGS=$(grep -v '^\s*#' "$HERE/packages.txt" | awk '{print $1}' | grep . | paste -sd,)

# RetroArch: the source-built KMS/GLES .deb through a local apt source (copy://, generated here; no
# binary in the repo). It Provides retroarch + libretro-frontend, so noble's libretro-* cores still install.
LOCAL_SRC=()
L="$OUT/tmp/localrepo"; mkdir -p "$L"
if [ -n "${RETROARCH_DEB:-}" ]; then
	cp "$RETROARCH_DEB" "$L/"
	PKGS=",$PKGS,"; PKGS=${PKGS/,retroarch,/,reduxos-retroarch,}; PKGS=${PKGS#,}; PKGS=${PKGS%,}
elif [ "${ALLOW_NOBLE_RETROARCH:-0}" = 1 ]; then
	# dev only: noble's retroarch links Qt/X11/Wayland/Pulse; its hard dependency on retroarch-assets
	# (~440 MB of fonts) is met by a tiny generated shim (rgui needs no assets)
	echo "WARNING: ALLOW_NOBLE_RETROARCH=1: noble's desktop-linked retroarch; not a release image" >&2
	S="$OUT/tmp/ra-slim"; mkdir -p "$S/DEBIAN" "$S/usr/share/doc/reduxos-retroarch-slim"
	printf '%s\n' "Package: reduxos-retroarch-slim" "Version: 1.0" "Architecture: all" \
	  "Maintainer: ReduxOS <noreply@example.invalid>" "Provides: retroarch-assets (= 1.20.0+reduxos1)" \
	  "Conflicts: retroarch-assets" "Description: ReduxOS shim: retroarch without the asset/font pack" \
	  " rgui needs no assets; install retroarch-assets for the xmb/ozone menus." > "$S/DEBIAN/control"
	printf '%s\n' "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/" \
	  "Upstream-Name: reduxos-retroarch-slim" "Source: image/build-image.sh (ReduxOS)" "" \
	  "Files: *" "Copyright: ReduxOS contributors" "License: GPL-2.0-only" \
	  " On Debian systems, the full text is in /usr/share/common-licenses/GPL-2." \
	  > "$S/usr/share/doc/reduxos-retroarch-slim/copyright"
	dpkg-deb --root-owner-group -Zxz --build "$S" "$L/reduxos-retroarch-slim_1.0_all.deb" >/dev/null
	PKGS="$PKGS,reduxos-retroarch-slim"
else
	echo "set RETROARCH_DEB=<reduxos-retroarch .deb> (tools/build-retroarch.sh); ALLOW_NOBLE_RETROARCH=1 for a dev image" >&2
	exit 2
fi
if ls "$L"/*.deb >/dev/null 2>&1; then
	(cd "$L" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null)
	LOCAL_SRC=("deb [trusted=yes] copy://$L ./")
fi
[ "$KMODE" = ubuntu ] && PKGS="$PKGS,initramfs-tools,linux-image-$UBUNTU_KVER,linux-modules-extra-$UBUNTU_KVER"

# Our kernel boots without an initramfs; only Ubuntu's QEMU-test kernel needs one (virtio + ext4).
INITRD_HOOK=()
[ "$KMODE" = ubuntu ] && INITRD_HOOK=(--setup-hook='mkdir -p "$1/etc/initramfs-tools/conf.d" && echo MODULES=list > "$1/etc/initramfs-tools/conf.d/h700.conf" && printf "virtio_blk\nvirtio_pci\next4\n" > "$1/etc/initramfs-tools/modules"')

# Everything that runs inside the new rootfs, as one script (clearer than a wall of one-line hooks).
CUSTOMIZE="$OUT/tmp/customize.sh"
cat > "$CUSTOMIZE" <<'EOS'
#!/bin/bash
# runs on the host with $1 = the rootfs; anything that must run inside uses chroot
set -euo pipefail
R=$1
ch() { chroot "$R" "$@"; }

cp -a "$IMG_HERE/rootfs/." "$R/"
sed -i "s|@ROOT@|$IMG_ROOT|" "$R/etc/default/u-boot"
chmod 0755 "$R"/usr/local/bin/* "$R"/usr/local/sbin/* "$R"/usr/local/libexec/* \
	"$R"/etc/kernel/postinst.d/zzz-h700-fallback "$R"/etc/kernel/postrm.d/zzz-h700-fallback

if [ -n "${KERNEL_DEB:-}" ]; then
	cp "$KERNEL_DEB" "$R/tmp/kernel.deb" && ch dpkg -i /tmp/kernel.deb && rm -f "$R/tmp/kernel.deb"
fi
ch u-boot-update

echo "$IMG_DEVICE" > "$R/etc/hostname"; printf '127.0.1.1\t%s\n' "$IMG_DEVICE" >> "$R/etc/hosts"
printf 'LABEL=rootfs\t/\text4\tdefaults,noatime\t0\t1\nLABEL=BOOT\t/boot\tvfat\tdefaults,noatime,umask=0077\t0\t2\n' > "$R/etc/fstab"
printf '[Match]\nName=en* eth*\n[Network]\nDHCP=yes\n' > "$R/etc/systemd/network/20-wired.network"
mkdir -p "$R/etc/iwd"
printf '[General]\nEnableNetworkConfiguration=true\n[Network]\nNameResolvingService=systemd\n' > "$R/etc/iwd/main.conf"

ch systemctl enable systemd-networkd iwd earlyoom nftables h700-firstboot.service h700-boot-ok.service \
	triggerhappy.service reduxos-audio-init.service reduxos-roms-setup.service reduxos-playlists.service
# SSH is off until the owner provisions a key (h700-firstboot); no fetches of motd.ubuntu.com
ch systemctl disable ssh.service ssh.socket 2>/dev/null || true
ch systemctl disable motd-news.timer e2scrub_all.timer e2scrub_reap.service 2>/dev/null || true

# Accounts. No credential ships: every password is locked and no SSH key is installed.
#   player: unprivileged, autologin on tty1 only (RetroArch); not in sudo
#   redux:  admin (sudo); key-only once the owner provisions /boot/reduxos/authorized_keys
grp() { for g in "$@"; do ch getent group "$g" >/dev/null && printf '%s,' "$g"; done; }
G=$(grp video render input audio); ch useradd -m -s /bin/bash -G "${G%,}" player
ch passwd -l player >/dev/null
install -m 0644 "$R/etc/reduxos-skel-player/.bash_profile" "$R/home/player/.bash_profile"
ch chown player:player /home/player/.bash_profile; rm -rf "$R/etc/reduxos-skel-player"
G=$(grp sudo video render input audio); ch useradd -m -s /bin/bash -G "${G%,}" redux
ch passwd -l redux >/dev/null
printf 'redux ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$R/etc/sudoers.d/60-reduxos-admin"; chmod 0440 "$R/etc/sudoers.d/60-reduxos-admin"
ch passwd -l root >/dev/null
rm -f "$R"/etc/ssh/ssh_host_* "$R/var/lib/dbus/machine-id" "$R/root/.ssh/authorized_keys"

# Injected components (never committed)
LR="$R/usr/lib/aarch64-linux-gnu/libretro"
if [ -n "${OSK_POINTER:-}" ]; then
	install -D -m 0755 "$OSK_POINTER" "$R/usr/local/bin/redux-osk-pointer"; echo "injected redux-osk-pointer"
fi
if [ -n "${CORES_DIR:-}" ]; then
	mkdir -p "$LR" "$R/usr/share/doc/reduxos-cores"
	for f in "$CORES_DIR"/*_libretro.so; do install -m 0644 "$f" "$LR/"; done
	[ -d "$CORES_DIR/licences" ] && cp -a "$CORES_DIR/licences/." "$R/usr/share/doc/reduxos-cores/"
	[ -f "$CORES_DIR/BUILD-SUMMARY.tsv" ] && cp "$CORES_DIR/BUILD-SUMMARY.tsv" "$R/usr/share/doc/reduxos-cores/"
	echo "injected $(ls "$CORES_DIR"/*_libretro.so | wc -l) source-built cores"
fi
if [ -n "${PORTMASTER_ZIP:-}" ]; then
	mkdir -p "$R/opt/tools" && unzip -q -o "$PORTMASTER_ZIP" -d "$R/opt/tools/"
	install -D -m 0644 "$IMG_HERE/portmaster/launch_hooks.txt" "$R/opt/tools/PortMaster/reduxos/launch_hooks.txt"
	ch chown -R player:player /opt/tools/PortMaster
	echo "injected PortMaster $(cat "$R/opt/tools/PortMaster/version" 2>/dev/null || echo '?')"
fi

ch dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' > "$R/root/manifest.tsv"
mkdir -p "$IMG_OUT/tmp/boot" && cp -a "$R/boot/." "$IMG_OUT/tmp/boot/" && umount "$R/boot"
EOS
chmod 0755 "$CUSTOMIZE"
export IMG_HERE="$HERE" IMG_ROOT="$ROOT" IMG_DEVICE="$DEVICE" IMG_OUT="$OUT"
export KERNEL_DEB="${KERNEL_DEB:-}" OSK_POINTER="${OSK_POINTER:-}" CORES_DIR="${CORES_DIR:-}" PORTMASTER_ZIP="${PORTMASTER_ZIP:-}"

log "1. rootfs ($SUITE, $(echo "$PKGS" | tr , '\n' | wc -l) packages requested, kernel: $KMODE, device: $DEVICE)"
# /boot is a separate tmpfs while packages install, so u-boot-menu sees a separate /boot (as on the
# card) and writes FAT-relative paths; its content becomes the FAT partition.
mmdebstrap --variant=minbase --arch=arm64 --components=main,universe \
  --include="$PKGS" \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt='path-exclude=/usr/share/doc/*' --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --dpkgopt='path-exclude=/usr/share/man/*' --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-include=/usr/share/locale/locale.alias' \
  --dpkgopt='force-confdef' --dpkgopt='force-confold' \
  --setup-hook='mkdir -p "$1/boot" && mount -t tmpfs -o size=512m h700boot "$1/boot"' \
  --setup-hook='mkdir -p "$1/etc/kernel" && printf "do_symlinks = no\n" > "$1/etc/kernel-img.conf"' \
  "${INITRD_HOOK[@]}" \
  --setup-hook="mkdir -p \"\$1/etc/default\" && sed 's|@ROOT@|$ROOT|' '$HERE/rootfs/etc/default/u-boot' > \"\$1/etc/default/u-boot\"" \
  --customize-hook="'$CUSTOMIZE' \"\$1\"" \
  "$SUITE" "$OUT/rootfs" \
  "deb $MIRROR $SUITE main universe" "deb $MIRROR $SUITE-updates main universe" \
  "deb $MIRROR $SUITE-security main universe" "${LOCAL_SRC[@]}"

log "2. stage /boot content into the rootfs tree for genimage"
# mmdebstrap empties /etc/machine-id at the end; systemd only runs ConditionFirstBoot= units (and makes a
# fresh per-unit id) when it reads "uninitialized", so set it after mmdebstrap.
echo uninitialized > "$OUT/rootfs/etc/machine-id"
rm -rf "$OUT/rootfs/boot"; mkdir -p "$OUT/rootfs/boot"; cp -a "$OUT/tmp/boot/." "$OUT/rootfs/boot/"
cp "$OUT/rootfs/root/manifest.tsv" "$OUT/$NAME.manifest.tsv"
# Our identity file. /etc/os-release stays as Ubuntu's base-files ships it (unmodified package).
printf 'NAME="ReduxOS"\nID=reduxos\nBUILD_ID=%s\nIMAGE_ID=%s\nDEVICE=%s\nBASE="Ubuntu 24.04 LTS (noble) packages"\nHOME_URL="https://github.com/wilcox101-maker/ReduxOS-Allwinner-H700"\nUBOOT=%s\n' \
	"$STAMP" "$NAME" "$DEVICE" "$(basename "${UBOOT_BIN:-none}" .bin)" > "$OUT/rootfs/etc/reduxos-release"
if [ -n "$UBOOT_DRAM" ]; then
	install -D -m 0644 "$UBOOT_NOTICES" "$OUT/rootfs/usr/share/doc/reduxos-bootloader/NOTICES.txt"
fi
# source package list, for publishing the matching source bundle with a release image
dpkg-query --admindir="$OUT/rootfs/var/lib/dpkg" -W -f='${source:Package}\t${source:Version}\n' | LC_ALL=C sort -u > "$OUT/$NAME.sources.tsv"
ROOT_KB=$(du -sxk --exclude=./boot "$OUT/rootfs" | cut -f1)
ROOT_MB=$(( ROOT_KB / 1024 * 120 / 100 + 64 ))           # content + 20 % + 64 MiB; grown on first boot
log "   root content $((ROOT_KB / 1024)) MiB -> partition $ROOT_MB MiB; /boot $(du -sm "$OUT/rootfs/boot" | cut -f1) MiB of $BOOT_MB"

log "3. genimage"
UBOOT_PART=""
if [ -n "${UBOOT_BIN:-}" ]; then
	cp "$UBOOT_BIN" "$OUT/genimage/u-boot-sunxi-with-spl.bin"
	UBOOT_PART=$'\tpartition u-boot {\n\t\tin-partition-table = false\n\t\timage = "u-boot-sunxi-with-spl.bin"\n\t\toffset = 8K\n\t\tsize = 1016K\n\t}'
fi
sed -e "s|@BOOT_MB@|$BOOT_MB|" -e "s|@ROOT_MB@|$ROOT_MB|" -e "s|@IMAGE@|$NAME.img|" -e "s|@DISK_SIG@|$DISK_SIG|" \
    "$HERE/genimage.cfg.in" | awk -v u="$UBOOT_PART" '{ if ($0 == "@UBOOT_PART@") { if (u != "") print u } else print }' \
    > "$OUT/genimage.cfg"
genimage --config "$OUT/genimage.cfg" --rootpath "$OUT/rootfs" --tmppath "$OUT/genimage/tmp" \
         --inputpath "$OUT/genimage" --outputpath "$OUT/genimage" >"$OUT/genimage.log" 2>&1 \
  || { tail -20 "$OUT/genimage.log"; exit 1; }
mv "$OUT/genimage/$NAME.img" "$OUT/"
if [ -n "$UBOOT_DRAM" ]; then
	log "4. boot layout check (SPL at 8 KiB, FAT at 16 MiB, DTBs, fw_env, DRAM type)"
	python3 -I "$HERE/check-boot-layout.py" "$OUT/$NAME.img" "$UBOOT_BIN" | tee "$OUT/$NAME.boot-layout.txt" ||
		{ echo "boot layout check failed; image left at $OUT/$NAME.img for inspection" >&2; exit 1; }
fi
(cd "$OUT" && sha256sum "$NAME.img" > "$NAME.img.sha256")
log "done: $OUT/$NAME.img ($(du -h --apparent-size "$OUT/$NAME.img" | cut -f1)); $ROOT"
