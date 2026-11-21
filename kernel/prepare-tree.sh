#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# prepare-tree.sh — prepare the ReduxOS H700 kernel tree and run the desk checks on it.
# Nothing here touches a device, a card or a disk image.
#
#   1. fetches torvalds/linux at the pinned commit into $WORK/linux (shallow)
#   2. applies kernel/patches/*.patch on a local "reduxos" branch, then the base layer
#      (kernel/upstream/base-layer.txt: upstream patchwork series by reference, tools/apply_upstream.py)
#   3. copies kernel/dts/* in and adds the ReduxOS board trees to the dts Makefile (uncommitted)
#   4. builds and schema-checks the RG34XX-SP DTBs (CHECK_DTBS=y): any warning fails
#   5. builds every C file the patches touch with W=1: any warning fails
#   6. checkpatch on every patch (--no-signoff: Signed-off-by is added by a human, never by a tool)
#   With --bindings, also runs dt_binding_check for the touched schemas (slow).
# Then run kernel/build-kernel.sh.
#
# Usage:  kernel/prepare-tree.sh [--bindings] [--no-checks]
#   WORK=<dir>  work directory (default ./.work; never committed)
# Needs (Ubuntu 24.04): git make gcc gcc-aarch64-linux-gnu bc flex bison libssl-dev device-tree-compiler
#   python3, curl; for --bindings and the DTB schema check: pip install dtschema yamllint
set -euo pipefail

LINUX_URL=https://github.com/torvalds/linux.git
LINUX_SHA=97d73c8251226cf27cc6656b4c542869bb8c69fa   # 2026-11-13, after v7.4-rc2 (untagged)
LINUX_SINCE=2026-11-08                                # v7.4-rc2 date, for the shallow fallback

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); REPO=$(dirname "$HERE")
WORK=${WORK:-$REPO/.work}
BINDINGS=0; CHECKS=1
while [ $# -gt 0 ]; do
	case "$1" in
	--bindings) BINDINGS=1 ;;
	--no-checks) CHECKS=0 ;;
	-h|--help) sed -n '2,21p' "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

# Local commits in the kernel tree (git am, tools/apply_upstream.py) keep each patch's author; the
# committer is this fixed identity, so a host without a git identity (CI runners) works and builds match.
export GIT_COMMITTER_NAME=reduxos GIT_COMMITTER_EMAIL=reduxos@invalid
log() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for tool in git make gcc aarch64-linux-gnu-gcc dtc python3 curl; do
	command -v "$tool" >/dev/null || fail "missing tool: $tool"
done

mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
LINUX=$WORK/linux
DTS=arch/arm64/boot/dts/allwinner
OUT=$WORK/kbuild-check
MAKE=(make -s -C "$LINUX" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)")

log "1. Linux at ${LINUX_SHA:0:12}"
if [ ! -d "$LINUX/.git" ]; then
	git init -q "$LINUX"
	git -C "$LINUX" remote add origin "$LINUX_URL"
fi
if ! git -C "$LINUX" cat-file -e "$LINUX_SHA^{commit}" 2>/dev/null; then
	git -C "$LINUX" fetch -q --depth 1 origin "$LINUX_SHA" 2>/dev/null ||
		git -C "$LINUX" fetch -q --shallow-since="$LINUX_SINCE" origin master
fi
git -C "$LINUX" cat-file -e "$LINUX_SHA^{commit}" || fail "could not fetch $LINUX_SHA"

log "2. Patches (kernel/patches), then the base layer by reference"
git -C "$LINUX" am --abort >/dev/null 2>&1 || true
git -C "$LINUX" checkout -q -f -B reduxos "$LINUX_SHA"
git -C "$LINUX" clean -q -fdx
git -C "$LINUX" -c user.name=reduxos -c user.email=reduxos@invalid am -q "$HERE"/patches/*.patch
python3 -I "$REPO/tools/apply_upstream.py" "$HERE/upstream/base-layer.txt" "$LINUX" --cache "$WORK/upstream-cache"
git -C "$LINUX" log --oneline "$LINUX_SHA"..HEAD

log "3. ReduxOS device trees (copied in, not committed to the kernel tree)"
cp "$HERE"/dts/*.dts "$HERE"/dts/*.dtsi "$LINUX/$DTS/"
line='dtb-$(CONFIG_ARCH_SUNXI) += sun50i-h700-anbernic-rg34xx-sp-redux.dtb'
grep -qxF "$line" "$LINUX/$DTS/Makefile" || echo "$line" >>"$LINUX/$DTS/Makefile"
# Our board trees are never part of a patch (step 3 adds them to the Makefile, uncommitted).
if grep -l 'rg34xx-sp-redux' "$HERE"/patches/*.patch; then
	fail "a patch above names a local -redux tree (stray Makefile hunk?)"
fi
if [ "$CHECKS" = 0 ]; then log "Tree ready in $LINUX (checks skipped)."; exit 0; fi

log "4. dtbs_check (any output counts as a failure)"
"${MAKE[@]}" defconfig >/dev/null
DTBS=(sun50i-h700-anbernic-rg34xx-sp sun50i-h700-anbernic-rg34xx-sp-redux)
targets=(); for d in "${DTBS[@]}"; do targets+=("allwinner/$d.dtb"); done
if python3 -c 'import dtschema' 2>/dev/null; then
	msgs=$("${MAKE[@]}" CHECK_DTBS=y "${targets[@]}" 2>&1) || fail "DTB build failed: $msgs"
	[ -z "$msgs" ] || { printf '%s\n' "$msgs"; fail "dtbs_check reported problems"; }
	chk="schema-checked"
else
	msgs=$("${MAKE[@]}" "${targets[@]}" 2>&1) || fail "DTB build failed: $msgs"
	[ -z "$msgs" ] || { printf '%s\n' "$msgs"; fail "DTB build warnings"; }
	chk="built (no dtschema installed: schema check skipped)"
fi
for d in "${DTBS[@]}"; do
	printf '  %-40s %6d bytes, 0 warnings, %s\n' "$d.dtb" "$(stat -c %s "$OUT/$DTS/$d.dtb")" "$chk"
done

log "5. W=1 build of every C file the patches touch (any warning counts as a failure)"
"$LINUX/scripts/config" --file "$OUT/.config" -m SND_SUN4I_CODEC
"${MAKE[@]}" olddefconfig >/dev/null
mapfile -t CFILES < <(git -C "$LINUX" diff --name-only "$LINUX_SHA" HEAD -- '*.c')
for c in "${CFILES[@]}"; do
	o=${c%.c}.o; rm -f "$OUT/$o"
	msgs=$("${MAKE[@]}" W=1 "$o" 2>&1) || { printf '%s\n' "$msgs"; fail "W=1 build: $c"; }
	[ -z "$msgs" ] || { printf '%s\n' "$msgs"; fail "W=1 warnings: $c"; }
	[ -f "$OUT/$o" ] || fail "W=1 build: $o not produced (driver not enabled?)"
	echo "  ok  $c"
done

log "6. checkpatch"
for p in "$HERE"/patches/*.patch; do
	res=$("$LINUX/scripts/checkpatch.pl" -q --no-signoff --terse "$p" 2>&1 || true)
	# A new board .dts always draws the MAINTAINERS reminder; the directory is already covered.
	res=$(printf '%s\n' "$res" | grep -v 'does MAINTAINERS need updating' |
		grep -v -E '^total: 0 errors, [01] warnings' | grep -v -E '^\s*$' || true)
	[ -z "$res" ] || { printf '%s\n' "$res"; fail "checkpatch: $(basename "$p")"; }
	echo "  ok  $(basename "$p")"
done

if [ "$BINDINGS" = 1 ]; then
	log "7. dt_binding_check"
	for s in sound/allwinner,sun4i-a10-codec.yaml opp/allwinner,sun50i-h6-operating-points.yaml arm/sunxi.yaml; do
		msgs=$(make -s -C "$LINUX" O="$OUT" ARCH=arm64 dt_binding_check DT_SCHEMA_FILES="$s" 2>&1) ||
			fail "dt_binding_check $s: $msgs"
		[ -z "$msgs" ] || { printf '%s\n' "$msgs"; fail "dt_binding_check reported problems in $s"; }
		echo "  ok  $s"
	done
fi
log "Tree ready in $LINUX; desk checks passed. Nothing here has run on hardware."
