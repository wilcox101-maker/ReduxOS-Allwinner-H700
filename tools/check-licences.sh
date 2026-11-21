#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# check-licences.sh — verify every component of a built ReduxOS rootfs is accounted for in PROVENANCE.md
# with a licence, and that no stock/vendor, BIOS or ROM material is present. Read-only; runs on the build
# host against the staged tree (dpkg-query --admindir, no chroot).
# usage: tools/check-licences.sh <rootfs-dir | out-dir containing rootfs/>
#   ALLOW_NC=1  accept non-commercially licensed cores (private builds only; never a published release)
#
#   1. every installed package keeps its copyright file (Ubuntu packages: PROVENANCE "Ubuntu base userspace")
#   2. every source-built / injected component maps to a PROVENANCE.md row:
#      reduxos-retroarch (version = pinned RetroArch), each *_libretro.so not owned by a package (its core
#      name in the cores table, with that row's commit = the built pin when BUILD-SUMMARY.tsv is present),
#      PortMaster (tag), redux-osk-pointer; every other file under /usr/local and /opt must come from
#      image/rootfs/ in this repo
#   3. firmware: every file under /usr/lib/firmware belongs to an installed package (no hand-dropped blobs)
#   4. forbidden content: panel init blobs (*.panel), stock boot/firmware dumps (boot0*.bin, boot_package*,
#      *.fex), any BIOS file named in systems.tsv, and any file in /roms other than the ReduxOS READMEs
# Exit 0 = all checks passed; 1 = at least one failed (each failure printed).
set -euo pipefail
R=${1:?usage: $0 <rootfs-or-out-dir>}
[ -d "$R/rootfs/etc" ] && R=$R/rootfs
R=$(cd "$R" && pwd)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROV=$REPO/PROVENANCE.md
ADMIN=$R/var/lib/dpkg
[ -f "$ADMIN/status" ] || { echo "no dpkg database in $R" >&2; exit 2; }
[ -f "$PROV" ] || { echo "no $PROV" >&2; exit 2; }
fail=0
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }
owned=$(mktemp); trap 'rm -f "$owned"' EXIT
cat "$ADMIN"/info/*.list | sed -e 's|^/lib/|/usr/lib/|' -e 's|^/bin/|/usr/bin/|' -e 's|^/sbin/|/usr/sbin/|' | sort -u > "$owned"
is_owned() { grep -qxF "$1" "$owned"; }
# a PROVENANCE.md table row whose first cell is exactly $1 (backticks allowed)
prov_row() { grep -E "^\| *\`?$1\`? *\|" "$PROV" | head -1; }

# 1. copyright files. A package's doc dir may be a relative symlink to another package's.
n=0
while read -r pkg; do
	n=$((n + 1))
	d=$R/usr/share/doc/${pkg%%:*}
	if [ -L "$d" ]; then t=$(readlink "$d"); case $t in /*) d=$R$t ;; *) d=$(dirname "$d")/$t ;; esac; fi
	[ -e "$d/copyright" ] || bad "no copyright file for package $pkg"
done < <(dpkg-query --admindir="$ADMIN" -W -f='${db:Status-Abbrev} ${binary:Package}\n' | awk '$1 ~ /^ii/ {print $2}')
echo "1. copyright files: $n installed packages"
prov_row 'Ubuntu base userspace' >/dev/null || bad "PROVENANCE.md has no 'Ubuntu base userspace' row"

# 2. source-built / injected components
ra=$(dpkg-query --admindir="$ADMIN" -W -f='${Version}' reduxos-retroarch 2>/dev/null || true)
if [ -n "$ra" ]; then
	row=$(prov_row RetroArch) || true
	[ -n "$row" ] || bad "reduxos-retroarch installed but PROVENANCE.md has no RetroArch row"
	v=${ra%%-*}; printf '%s' "$row" | grep -q "v$v" || bad "reduxos-retroarch $ra: PROVENANCE RetroArch row does not pin v$v"
	echo "2a. reduxos-retroarch $ra -> PROVENANCE RetroArch row"
fi
LR=$R/usr/lib/aarch64-linux-gnu/libretro
SUM=$R/usr/share/doc/reduxos-cores/BUILD-SUMMARY.tsv
nc=0; nb=0
for so in "$LR"/*_libretro.so; do
	[ -e "$so" ] || continue
	is_owned "${so#"$R"}" && continue                    # from a noble libretro-* package (step 1 covers it)
	core=$(basename "$so" _libretro.so); nb=$((nb + 1))
	row=$(prov_row "$core") || true
	if [ -z "$row" ]; then bad "core $core: no PROVENANCE.md row"; continue; fi
	if [ "$core" != redux_exec ] && [ -f "$SUM" ]; then
		pin=$(awk -F'\t' -v c="$core" '$1==c {print $3}' "$SUM")
		[ -n "$pin" ] && ! printf '%s' "$row" | grep -q "$pin" && bad "core $core: built at $pin, PROVENANCE.md row pins another commit"
		lic=$(awk -F'\t' -v c="$core" '$1==c {print $6}' "$SUM")
		case $lic in nc*) nc=$((nc + 1)); [ "${ALLOW_NC:-0}" = 1 ] || bad "core $core: non-commercial licence ($lic) in the image (ALLOW_NC=1 for a private build only)" ;; esac
	fi
	[ -d "$R/usr/share/doc/reduxos-cores/$core" ] || [ "$core" = redux_exec ] || bad "core $core: no licence files in /usr/share/doc/reduxos-cores/$core"
done
echo "2b. source-built cores: $nb checked against PROVENANCE.md, $nc non-commercial"
if [ -d "$R/opt/tools/PortMaster" ]; then
	row=$(prov_row PortMaster) || true
	[ -n "$row" ] || bad "PortMaster injected but PROVENANCE.md has no PortMaster row"
	echo "2c. PortMaster -> PROVENANCE row"
fi
if [ -e "$R/usr/local/bin/redux-osk-pointer" ]; then
	prov_row redux-osk-pointer >/dev/null || bad "redux-osk-pointer: no PROVENANCE.md row"
fi
# everything else under /usr/local and /opt (outside PortMaster) must come from this repo's image/rootfs/
stray=0
while IFS= read -r f; do
	p=${f#"$R"}
	case $p in /opt/tools/PortMaster/*|/usr/local/bin/redux-osk-pointer) continue ;; esac
	is_owned "$p" && continue
	# base-files' relative links inside /usr/local (e.g. man -> share/man)
	if [ -L "$f" ]; then case $(readlink "$f") in /*|*..*) ;; *) continue ;; esac; fi
	[ -e "$REPO/image/rootfs$p" ] || { bad "unaccounted file (not from a package or image/rootfs/): $p"; stray=$((stray + 1)); }
done < <(find "$R/usr/local" "$R/opt" \( -type f -o -type l \) 2>/dev/null)
echo "2d. /usr/local + /opt: $stray unaccounted files"

# 3. firmware ownership
fw=0
if [ -d "$R/usr/lib/firmware" ]; then
	while IFS= read -r f; do
		fw=$((fw + 1)); is_owned "${f#"$R"}" || bad "firmware file not owned by any package: ${f#"$R"}"
	done < <(find "$R/usr/lib/firmware" \( -type f -o -type l \))
fi
echo "3. firmware ownership: $fw files under /usr/lib/firmware"

# 4. forbidden content
while IFS= read -r f; do bad "panel blob: ${f#"$R"}"; done < <(find "$R" -xdev -name '*.panel' 2>/dev/null)
while IFS= read -r f; do bad "stock boot/firmware dump: ${f#"$R"}"; done < <(find "$R/boot" "$R/usr/lib/firmware" \
	\( -iname 'boot0*.bin' -o -iname 'boot_package*' -o -iname '*.fex' \) 2>/dev/null)
SYS=$R/usr/share/reduxos/systems.tsv
if [ -f "$SYS" ]; then
	nb=0
	while IFS= read -r b; do
		[ -n "$b" ] || continue; nb=$((nb + 1))
		while IFS= read -r f; do bad "BIOS file in the image: ${f#"$R"}"; done < <(find "$R" -xdev -type f -name "$b" 2>/dev/null)
	done < <(awk -F'\t' '!/^#/ && $4 != "-" && $4 != "" {print $4}' "$SYS" | tr ';' '\n' | sort -u)
	echo "4a. BIOS filename scan: $nb names from systems.tsv"
fi
while IFS= read -r f; do bad "content in /roms (ROM/BIOS/save?): ${f#"$R"}"; done < <(find "$R/roms" -type f ! -name .keep ! -name README.txt 2>/dev/null)
echo "4b. panel blob, stock dump and /roms content scan: done"

[ $fail = 0 ] && echo "licence checks: PASS" || echo "licence checks: FAIL"
exit $fail
