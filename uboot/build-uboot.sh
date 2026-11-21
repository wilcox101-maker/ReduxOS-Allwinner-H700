#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# build-uboot.sh — build TF-A BL31 + SPL + u-boot for the RG34XX-SP: one binary per DRAM type (LPDDR4,
# LPDDR3), written raw at 8 KiB of the card image by image/build-image.sh (UBOOT_BIN=...). Nothing here
# touches a device, card or disk image.
#
#   1. fetches TF-A and u-boot at pinned commits into $WORK (shallow)
#   2. builds TF-A BL31 for sun50i_h616 once
#   3. per DRAM type: anbernic_rg35xx_h700_defconfig + uboot/config/rg34xxsp.config (+ lpddr3.config),
#      uboot/patches/*.patch, then make with BL31; checks every fragment line holds
#   4. checks the binary: eGON SPL header and checksum, size within the card gap (8 KiB .. 1 MiB), the PE6
#      DT-selection and boot-limit fallback code present; writes u-boot-rg34xxsp-<dram>-<uboot ver>.bin, its
#      .config and SHA256SUMS to $OUT
#   5. writes u-boot-rg34xxsp-<ver>-NOTICES.txt: the licence notices of every file compiled into the
#      binaries (tools/bootloader_notices.py); it must ship with any image that carries them
#
# Usage:  uboot/build-uboot.sh [--dram lpddr4|lpddr3|all] [--sources] [--config-only] [--jobs N]
#   --config-only  steps 1 and 3 up to the .config checks (fragments, DRAM type, DRAM size cap), then stop:
#              no TF-A, no compile; needs only host gcc, make, flex, bison (CI)
#   --sources  also write the corresponding source (GPL/BSD): pristine u-boot and TF-A
#              tarballs at the pinned commits, plus this repo's u-boot patches, fragments and script
#   WORK=<dir>  work directory (default ./.work);  OUT=<dir> results (default $WORK/u-boot-out)
# Needs (Ubuntu 24.04): gcc-aarch64-linux-gnu make bison flex bc swig python3-dev libssl-dev
#                       libgnutls28-dev device-tree-compiler, python3 pyelftools (binman)
# NOT BOOTED: a wrong SPL for the board's DRAM can leave the card unbootable (recover by rewriting
# the card); LPDDR3 SPL on an LPDDR4 board gives 1.2 V to 1.1 V memory.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); REPO=$(dirname "$HERE")
WORK=${WORK:-$REPO/.work}
OUT=${OUT:-$WORK/u-boot-out}
DRAMS=(lpddr4 lpddr3)
JOBS=$(nproc)
SOURCES=0
CONFIG_ONLY=0

UBOOT_URL=https://github.com/u-boot/u-boot.git
UBOOT_TAG=v2026.10
UBOOT_SHA=5508406582f6f7120dce0c4b3059819a41788db2
TFA_URL=https://github.com/ARM-software/arm-trusted-firmware.git
TFA_TAG=v2.14.0
TFA_SHA=1d5aa939bc8d3d892e2ed9945fa50e36a1a924cc
DEFCONFIG=anbernic_rg35xx_h700_defconfig
MAX_BYTES=$((1016 * 1024))   # 8 KiB .. 1 MiB: the gap image/genimage.cfg.in leaves before /boot

while [ $# -gt 0 ]; do
	case "$1" in
	--dram) case "${2:-}" in lpddr4|lpddr3) DRAMS=("$2") ;; all) ;; *) echo "--dram lpddr4|lpddr3|all" >&2; exit 2 ;; esac; shift ;;
	--sources) SOURCES=1 ;;
	--config-only) CONFIG_ONLY=1 ;;
	--jobs) JOBS=$2; shift ;;
	-h|--help) sed -n '2,25p' "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

log() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

fetch() {	# dir url tag sha
	local d=$1
	if [ ! -d "$d/.git" ]; then
		git init -q "$d"
		git -C "$d" remote add origin "$2"
	fi
	git -C "$d" cat-file -e "$4^{commit}" 2>/dev/null ||
		git -C "$d" fetch -q --depth 1 origin "refs/tags/$3:refs/tags/$3"
	[ "$(git -C "$d" rev-parse "$3^{commit}")" = "$4" ] || fail "$3 of $2 is not $4"
	git -C "$d" checkout -q -f "$4"
	git -C "$d" clean -q -fdx
}

mkdir -p "$WORK" "$OUT"
log "1. Sources: u-boot $UBOOT_TAG (${UBOOT_SHA:0:12}), TF-A $TFA_TAG (${TFA_SHA:0:12})"
fetch "$WORK/u-boot" "$UBOOT_URL" "$UBOOT_TAG" "$UBOOT_SHA"
[ "$CONFIG_ONLY" = 1 ] || fetch "$WORK/tf-a" "$TFA_URL" "$TFA_TAG" "$TFA_SHA"
for p in "$HERE"/patches/*.patch; do
	git -C "$WORK/u-boot" apply --index "$p" || fail "patch does not apply: $(basename "$p")"
	echo "  applied $(basename "$p")"
done

# Reproducible: date from the u-boot commit; no host/user in the version string.
SOURCE_DATE_EPOCH=$(git -C "$WORK/u-boot" log -1 --format=%ct)
export SOURCE_DATE_EPOCH

if [ "$CONFIG_ONLY" = 0 ]; then
log "2. TF-A BL31 (PLAT=sun50i_h616)"
make -s -C "$WORK/tf-a" CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_h616 DEBUG=0 \
	BUILD_STRING="$TFA_TAG" -j"$JOBS" bl31 >"$WORK/tf-a-build.log" 2>&1 ||
	{ tail -20 "$WORK/tf-a-build.log"; fail "TF-A build"; }
BL31=$WORK/tf-a/build/sun50i_h616/release/bl31.bin
[ -s "$BL31" ] || fail "no $BL31"
echo "  bl31.bin $(stat -c %s "$BL31") bytes"
fi

: >"$OUT/SHA256SUMS"
for dram in "${DRAMS[@]}"; do
	log "3. u-boot for $dram"
	B=$WORK/u-boot-build-$dram
	rm -rf "$B"; mkdir -p "$B"
	FRAGS=("$HERE/config/rg34xxsp.config")
	[ "$dram" = lpddr3 ] && FRAGS+=("$HERE/config/lpddr3.config")
	MAKE=(make -s -C "$WORK/u-boot" O="$B" CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= -j"$JOBS")
	"${MAKE[@]}" "$DEFCONFIG" >/dev/null
	(cd "$WORK/u-boot" && KCONFIG_CONFIG="$B/.config" scripts/kconfig/merge_config.sh -m -O "$B" \
		"$B/.config" "${FRAGS[@]}" >/dev/null)
	"${MAKE[@]}" olddefconfig >/dev/null
	bad=0
	while IFS= read -r line; do
		case "$line" in
		CONFIG_*=*) sym=${line%%=*}; want=$line ;;
		'# CONFIG_'*' is not set') sym=${line#\# }; sym=${sym%% *}; want="# $sym is not set" ;;
		*) continue ;;
		esac
		have=$(grep -E "^($sym=|# $sym is not set)" "$B/.config" || true)
		if [ "$have" != "$want" ] && ! { [ -z "$have" ] && [ "${want#\# }" != "$want" ]; }; then
			printf '  wanted %s\n     got %s\n' "$want" "${have:-(absent)}"; bad=1
		fi
	done < <(cat "${FRAGS[@]}")
	[ "$bad" = 0 ] || fail "$dram: config fragment did not apply cleanly"
	echo "  all $(cat "${FRAGS[@]}" | grep -c -E '^(CONFIG_|# CONFIG_)') fragment lines hold"
	grep -q "^CONFIG_SUNXI_DRAM_H616_${dram^^}=y" "$B/.config" || fail "$dram: wrong DRAM type in .config"
	# No cap below 2 GiB (2 GB units exist). The SPL measures the size
	# (rank/width, then rows/cols: arch/arm/mach-sunxi/dram_dw_helpers.c) and passes it in the SPL header;
	# u-boot proper's dram_init() (board/sunxi/board.c) clamps it to CONFIG_SUNXI_DRAM_MAX_SIZE. If upstream
	# moves that clamp, stop here so this check gets reviewed instead of passing on nothing.
	grep -qF 'gd->ram_size = CONFIG_SUNXI_DRAM_MAX_SIZE;' "$WORK/u-boot/board/sunxi/board.c" ||
		fail "board/sunxi/board.c no longer clamps gd->ram_size to SUNXI_DRAM_MAX_SIZE: review the DRAM cap check"
	max=$(sed -n 's/^CONFIG_SUNXI_DRAM_MAX_SIZE=//p' "$B/.config")
	[ -n "$max" ] && [ $((max)) -ge $((0x80000000)) ] ||
		fail "$dram: CONFIG_SUNXI_DRAM_MAX_SIZE=${max:-(absent)} caps DRAM below 2 GiB"
	echo "  DRAM cap CONFIG_SUNXI_DRAM_MAX_SIZE=$max (>= 2 GiB)"
	[ "$CONFIG_ONLY" = 1 ] && continue
	"${MAKE[@]}" BL31="$BL31" SCP=/dev/null >"$B/build.log" 2>&1 ||
		{ tail -30 "$B/build.log"; fail "$dram: u-boot build"; }

	log "4. Checks ($dram)"
	BIN=$B/u-boot-sunxi-with-spl.bin
	[ -s "$BIN" ] || fail "$dram: no u-boot-sunxi-with-spl.bin"
	size=$(stat -c %s "$BIN")
	[ "$size" -le "$MAX_BYTES" ] || fail "$dram: $size bytes, more than the $MAX_BYTES-byte card gap"
	[ "$(dd if="$BIN" bs=1 skip=4 count=8 status=none)" = "eGON.BT0" ] || fail "$dram: no eGON.BT0 SPL header"
	# The boot ROM loads the SPL only if the eGON checksum matches (sum of the SPL's 32-bit words
	# with the checksum field taken as 0x5F0A6C39).
	python3 -I - "$BIN" <<'PY' || fail "$dram: eGON SPL checksum or length wrong"
import struct, sys
b = open(sys.argv[1], 'rb').read()
chk, length = struct.unpack_from('<II', b, 0xc)
if length % 512 or length > len(b):
    sys.exit(1)
d = bytearray(b[:length])
struct.pack_into('<I', d, 0xc, 0x5F0A6C39)
sys.exit(0 if sum(struct.unpack_from('<%dI' % (length // 4), d)) & 0xffffffff == chk else 1)
PY
	low=$(sed -n 's/^CONFIG_ANBERNIC_RG34XXSP_DT_PE6_LOW="\(.*\)"$/\1/p' "$B/.config")
	for s in "RG34XX-SP: panel ID PE6=" "${low:?no PE6-low DT name}" \
		 "boot limit reached, booting fallback" "U-Boot SPL ${UBOOT_TAG#v}"; do
		grep -qaF "$s" "$BIN" || fail "$dram: binary lacks \"$s\""
	done
	name=u-boot-rg34xxsp-$dram-${UBOOT_TAG#v}
	cp "$BIN" "$OUT/$name.bin"
	cp "$B/.config" "$OUT/$name.config"
	(cd "$OUT" && sha256sum "$name.bin" >>SHA256SUMS)
	printf '  %s.bin  %s bytes (card gap %s), SPL header + checksum ok, PE6 + fallback code present\n' \
		"$name" "$size" "$MAX_BYTES"
done

if [ "$CONFIG_ONLY" = 1 ]; then
	log "Done (--config-only): fragments, DRAM type and DRAM size cap checked; nothing built."
	exit 0
fi

log "4b. Licence notices for the binaries (BSD/ISC/… notices must travel with the binary)"
UBUILDS=(); for d in "${DRAMS[@]}"; do UBUILDS+=(--uboot-build "$WORK/u-boot-build-$d"); done
python3 -I "$REPO/tools/bootloader_notices.py" --uboot-src "$WORK/u-boot" "${UBUILDS[@]}" \
	--tfa-src "$WORK/tf-a" --tfa-build "$WORK/tf-a/build/sun50i_h616/release" \
	>"$OUT/u-boot-rg34xxsp-${UBOOT_TAG#v}-NOTICES.txt" || fail "licence notices"
(cd "$OUT" && sha256sum "u-boot-rg34xxsp-${UBOOT_TAG#v}-NOTICES.txt" >>SHA256SUMS)
echo "  u-boot-rg34xxsp-${UBOOT_TAG#v}-NOTICES.txt ($(wc -l <"$OUT/u-boot-rg34xxsp-${UBOOT_TAG#v}-NOTICES.txt") lines)"

if [ "$SOURCES" = 1 ]; then
	log "5. Corresponding source"
	V=${UBOOT_TAG#v}
	git -C "$WORK/u-boot" archive --format=tar --prefix="u-boot-$V/" "$UBOOT_SHA" |
		xz -T0 -9 >"$OUT/u-boot-$V.tar.xz"
	git -C "$WORK/tf-a" archive --format=tar --prefix="trusted-firmware-a-${TFA_TAG#v}/" "$TFA_SHA" |
		xz -T0 -9 >"$OUT/trusted-firmware-a-${TFA_TAG#v}.tar.xz"
	git -C "$REPO" archive --format=tar --prefix="rg34xxsp-u-boot-inputs-$V/" HEAD \
		uboot tools/bootloader_notices.py tools/licences | xz -9 >"$OUT/rg34xxsp-u-boot-inputs-$V.tar.xz"
	(cd "$OUT" && sha256sum ./*.tar.xz | sed 's| \./| |' >>SHA256SUMS)
	ls -la "$OUT"/*.tar.xz | awk '{print "  " $5 "  " $9}'
fi

log "Done. Binaries in $OUT. NOT BOOTED: first use on a spare card (or over FEL), never the only card."
