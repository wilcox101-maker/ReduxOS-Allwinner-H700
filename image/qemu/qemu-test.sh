#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: qemu-test.sh IMAGE.img [MB] -> IMAGE.qemu-<MB>.log
# Boots a COPY of the image in QEMU (virt, Cortex-A53, TCG), kernel/initrd taken from its FAT partition,
# root from its partition 2 by PARTUUID. The copy is enlarged to 3 GiB to exercise first-boot growth and
# gets guest-check + frontend-check.py injected (debugfs) so it reports and powers off. The original image
# is never changed and nothing touches a block device. QEMU is not the H700: this proves userspace, first
# boot and image layout, not the board's hardware.
set -euo pipefail
IMG=$(readlink -f "$1"); MB=${2:-512}; HERE=$(cd "$(dirname "$0")" && pwd)
for t in qemu-system-aarch64 sfdisk mcopy mtype mdir debugfs; do
	command -v "$t" >/dev/null || { echo "missing host tool: $t" >&2; exit 2; }; done
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp --reflink=auto "$IMG" "$W/disk.img"; truncate -s 3G "$W/disk.img"
read -r P1 P2 < <(sfdisk -d "$W/disk.img" | awk -F'start= *' '/start=/{split($2,a,",");printf "%s ", a[1]} END{print ""}')
FAT="$W/disk.img@@$((P1*512))"
# kernel and initrd: plain names if present, else the versioned files u-boot-menu installs
pick() { mdir -b -i "$FAT" :: | sed 's|.*/||' | grep -m1 "^$1" || true; }
K=vmlinuz; mcopy -n -i "$FAT" "::/$K" "$W/vmlinuz" 2>/dev/null || { K=$(pick vmlinuz-); mcopy -n -i "$FAT" "::/$K" "$W/vmlinuz"; }
INITRD=(); I=$(pick initrd.img)
if [ -n "$I" ] && mcopy -n -i "$FAT" "::/$I" "$W/initrd" 2>/dev/null; then INITRD=(-initrd "$W/initrd"); fi
P2SIZE=$(sfdisk -d "$W/disk.img" | awk -F'size= *' '/img2/{split($2,a,",");print a[1]}')
dd if="$W/disk.img" of="$W/p2" bs=512 skip="$P2" count="$P2SIZE" status=none
inject() { debugfs -w -R "write $1 $2" "$W/p2" >/dev/null 2>&1; debugfs -w -R "sif $2 mode 0100755" "$W/p2" >/dev/null 2>&1; }
inject "$HERE/guest-check" /usr/local/sbin/guest-check
inject "$HERE/frontend-check.py" /usr/local/sbin/frontend-check.py
printf '[Unit]\nAfter=multi-user.target\n[Service]\nType=simple\nExecStart=/usr/local/sbin/guest-check\nStandardOutput=journal+console\n[Install]\nWantedBy=multi-user.target\n' > "$W/guest-check.service"
debugfs -w -R "write $W/guest-check.service /etc/systemd/system/guest-check.service" "$W/p2" >/dev/null 2>&1
debugfs -w -R "symlink /etc/systemd/system/multi-user.target.wants/guest-check.service /etc/systemd/system/guest-check.service" "$W/p2" >/dev/null 2>&1
dd if="$W/p2" of="$W/disk.img" bs=512 seek="$P2" conv=notrunc status=none
APPEND=$(mtype -i "$FAT" ::/extlinux/extlinux.conf | awk '/^[ \t]*append/{sub(/^[ \t]*append /,""); print; exit}' | sed 's/console=ttyS0,115200/console=ttyAMA0/; s/ quiet//')
OUTLOG="${IMG%.img}.qemu-$MB.log"
echo "kernel $K${INITRD:+, initrd $I}; append: $APPEND"
timeout 2400 qemu-system-aarch64 -M virt -cpu cortex-a53 -smp 4 -m "$MB" -nographic -no-reboot \
  -kernel "$W/vmlinuz" "${INITRD[@]}" -append "$APPEND" \
  -drive "file=$W/disk.img,format=raw,if=none,id=hd0" -device virtio-blk-device,drive=hd0 \
  -netdev user,id=n0 -device virtio-net-device,netdev=n0 > "$OUTLOG" 2>&1 || true
echo "log: $OUTLOG"
