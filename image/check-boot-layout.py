#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Check the boot layout of a ReduxOS card image that carries an H700 u-boot (SPL + u-boot, raw at 8 KiB).
Read-only: opens the image file, never a block device.

usage: check-boot-layout.py IMAGE [UBOOT_BIN]
  UBOOT_BIN  the u-boot-rg34xxsp-<dram>-<ver>.bin the image was built with (from the u-boot build (injected, never committed));
             its .config (same name, .config) is read if present.

What the Allwinner boot ROM and our u-boot need from the card, checked on the bytes:
  1. MBR: 0x55AA, disk signature 0x48373030; no GPT header at LBA 1 (a GPT entry array would cover 8 KiB)
  2. SPL at 8 KiB: 'eGON.BT0', length a multiple of 512, checksum valid (the BROM's own check)
  3. the 8 KiB region is byte-identical to UBOOT_BIN; it ends before 1 MiB; nothing else is written
     between its end and the first partition; no second eGON header at 128 KiB (the BROM's backup slot)
  4. partitions: p1 FAT32 (0x0c), bootable, at 16 MiB; p2 Linux; no partition starts below 16 MiB or overlaps
  5. DRAM type: the image name, the binary name and its .config agree (wrong type = 1.2 V on 1.1 V DRAM)
  6. /boot (FAT) holds what u-boot will ask for: extlinux.conf and extlinux-fallback.conf with fdtdir, both PE6 DTB names
     under dtb-<ver>/allwinner/ for every kernel the menu lists, a kernel image per entry
  7. fw_env.config in the root fs matches u-boot's CONFIG_ENV_SIZE and file name, no redundant env
  8. the bootloader's licence notices are in the root fs (/usr/share/doc/reduxos-bootloader/NOTICES.txt)
Exit 0 only if every check passes. Needs: python3, mtools (mtype/mdir), e2fsprogs (debugfs).
"""
import os
import re
import struct
import subprocess
import sys

KIB, MIB = 1024, 1024 * 1024
SPL_OFF = 8 * KIB
GAP_END = 1 * MIB            # genimage.cfg.in: u-boot partition 8K + 1016K
BOOT_OFF = 16 * MIB
DISK_SIG = 0x48373030
# The DTB u-boot picks for each PE6 level comes from its .config (next to the binary); these are the fallbacks.
DTBS = {"low": "sun50i-h700-anbernic-rg34xx-sp-redux.dtb", "high": "sun50i-h700-anbernic-rg34xx-sp-redux.dtb"}


def uboot_dtbs(ubin):
    """PE6 low/high DT names from the u-boot .config written next to the binary, if any."""
    cfg = os.path.splitext(ubin)[0] + ".config" if ubin else None
    out = dict(DTBS)
    if cfg and os.path.exists(cfg):
        for lvl in ("low", "high"):
            m = re.search(r'^CONFIG_ANBERNIC_RG34XXSP_DT_PE6_%s="(?:allwinner/)?([^"]+)"' % lvl.upper(), open(cfg).read(), re.M)
            if m:
                out[lvl] = m.group(1)
    return out

fails = []


def check(ok, msg):
    print(("  ok    " if ok else "  FAIL  ") + msg)
    if not ok:
        fails.append(msg)
    return ok


def egon_ok(buf):
    """(valid, spl_length) for an eGON.BT0 header at buf[0]."""
    if buf[4:12] != b"eGON.BT0":
        return False, 0
    chk, length = struct.unpack_from("<II", buf, 0xc)
    if length % 512 or length > len(buf) or length < 0x20:
        return False, length
    d = bytearray(buf[:length])
    struct.pack_into("<I", d, 0xc, 0x5F0A6C39)
    return sum(struct.unpack_from("<%dI" % (length // 4), d)) & 0xffffffff == chk, length


def mbr_parts(b):
    parts = []
    for i in range(4):
        e = b[446 + 16 * i: 462 + 16 * i]
        boot, ptype = e[0], e[4]
        lba, n = struct.unpack_from("<II", e, 8)
        if ptype:
            parts.append({"n": i + 1, "boot": boot == 0x80, "type": ptype, "start": lba * 512, "size": n * 512})
    return parts


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def main():
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    img = sys.argv[1]
    ubin = sys.argv[2] if len(sys.argv) == 3 else None
    size = os.path.getsize(img)
    with open(img, "rb") as f:
        head = f.read(BOOT_OFF)
    print("image %s (%d MiB)" % (os.path.basename(img), size // MIB))

    print("1. partition table")
    check(head[510:512] == b"\x55\xaa", "MBR signature 0x55AA")
    sig = struct.unpack_from("<I", head, 440)[0]
    check(sig == DISK_SIG, "disk signature 0x%08x (want 0x%08x, PARTUUIDs depend on it)" % (sig, DISK_SIG))
    check(head[512:520] != b"EFI PART", "no GPT header at LBA 1")
    parts = mbr_parts(head)

    print("2. SPL at 8 KiB (what the boot ROM checks)")
    ok, spl_len = egon_ok(head[SPL_OFF:])
    check(ok, "eGON.BT0 header and checksum valid, SPL %d bytes" % spl_len)

    print("3. u-boot region")
    end = None
    if ubin:
        with open(ubin, "rb") as f:
            want = f.read()
        end = SPL_OFF + len(want)
        check(head[SPL_OFF:end] == want, "bytes at 8 KiB == %s (%d bytes)" % (os.path.basename(ubin), len(want)))
    else:
        nz = [i for i in range(GAP_END - 1, SPL_OFF, -1) if head[i]]
        end = (nz[0] + 1) if nz else SPL_OFF
        print("  info  no UBOOT_BIN given; last non-zero byte before 1 MiB at 0x%x" % (end - 1))
    check(end <= GAP_END, "u-boot ends at 0x%x, inside the 8 KiB .. 1 MiB gap" % end)
    check(not any(head[512:SPL_OFF]), "512 B .. 8 KiB is empty (no GPT entries, nothing in front of the SPL)")
    first = min([p["start"] for p in parts] or [BOOT_OFF])
    check(not any(head[end:first]), "0x%x .. 0x%x (u-boot end .. first partition) is empty" % (end, first))
    if end <= 128 * KIB:
        check(head[128 * KIB + 4:128 * KIB + 12] != b"eGON.BT0", "no second SPL at 128 KiB")
    else:
        b128, _ = egon_ok(head[128 * KIB:])
        check(not b128, "the 128 KiB backup-SPL slot (inside our binary) holds no valid eGON header")

    print("4. partitions")
    check(len(parts) == 2, "two partitions (%d)" % len(parts))
    p = {q["n"]: q for q in parts}
    if 1 in p:
        q = p[1]
        check(q["type"] == 0x0c and q["boot"], "p1 FAT32 LBA (0x0c), bootable flag set")
        check(q["start"] == BOOT_OFF, "p1 starts at 16 MiB (0x%x)" % q["start"])
    if 2 in p:
        q = p[2]
        check(q["type"] == 0x83, "p2 Linux (0x83)")
        check(q["start"] >= p[1]["start"] + p[1]["size"] if 1 in p else True, "p2 after p1, no overlap")
        check(q["start"] + q["size"] <= size, "p2 inside the image")
    check(all(q["start"] >= end for q in parts), "no partition starts inside the u-boot region")

    print("5. DRAM type")
    m = re.search(r"-(lpddr4|lpddr3)(?:[-.]|$)", os.path.basename(img))
    img_dram = m.group(1) if m else None
    check(img_dram is not None, "image name carries the DRAM type (%s)" % img_dram)
    if ubin:
        m = re.match(r"u-boot-rg34xxsp-(lpddr4|lpddr3)-", os.path.basename(ubin))
        bin_dram = m.group(1) if m else None
        check(bin_dram == img_dram, "binary name DRAM type %s == image %s" % (bin_dram, img_dram))
        cfg = ubin[:-4] + ".config" if ubin.endswith(".bin") else None
        if cfg and os.path.exists(cfg):
            text = open(cfg).read()
            cfg_dram = "lpddr4" if "CONFIG_SUNXI_DRAM_H616_LPDDR4=y" in text else \
                       "lpddr3" if "CONFIG_SUNXI_DRAM_H616_LPDDR3=y" in text else None
            check(cfg_dram == img_dram, "u-boot .config DRAM type %s == image %s" % (cfg_dram, img_dram))
            mv = re.search(r"^CONFIG_AXP_DCDC3_VOLT=(\d+)", text, re.M)
            want_mv = {"lpddr4": 1100, "lpddr3": 1200}.get(img_dram)
            check(mv and int(mv.group(1)) == want_mv, "DCDC3 (vdd-dram) %s mV for %s" % (mv and mv.group(1), img_dram))
        else:
            cfg = None
            print("  info  no %s next to the binary; .config checks skipped" % "u-boot .config")
    else:
        cfg = None

    print("6. /boot (FAT) content")
    if 1 not in p:
        check(False, "no p1")
    else:
        fat = "%s@@%d" % (img, p[1]["start"])
        env = dict(os.environ, MTOOLS_SKIP_CHECK="1")
        r = subprocess.run(["mtype", "-i", fat, "::/extlinux/extlinux.conf"], capture_output=True, text=True, env=env)
        conf = r.stdout if r.returncode == 0 else ""
        check(bool(conf), "extlinux/extlinux.conf present")
        check(re.search(r"^\s*fdtdir\s", conf, re.M | re.I) is not None, "entries use fdtdir (u-boot's fdtfile picks the DTB)")
        r = subprocess.run(["mtype", "-i", fat, "::/extlinux/extlinux-fallback.conf"], capture_output=True, text=True, env=env)
        check(r.returncode == 0 and "fdtdir" in r.stdout,
              "extlinux/extlinux-fallback.conf present(u-boot altbootcmd: sysboot mmc 0:1 fat … /extlinux/extlinux-fallback.conf)")
        conf += r.stdout if r.returncode == 0 else ""
        kernels = sorted(set(re.findall(r"^\s*linux\s+(\S+)", conf, re.M | re.I)))
        fdtdirs = sorted(set(re.findall(r"^\s*fdtdir\s+(\S+)", conf, re.M | re.I)))
        check(len(kernels) >= 1, "menu lists %d kernel(s): %s" % (len(kernels), " ".join(kernels)))
        for k in kernels:
            r = subprocess.run(["mdir", "-b", "-i", fat, "::" + k], capture_output=True, text=True, env=env)
            check(r.returncode == 0, "kernel %s on the FAT" % k)
        for d in fdtdirs:
            for lvl, dtb in sorted(uboot_dtbs(ubin).items()):
                path = d.rstrip("/") + "/allwinner/" + dtb
                r = subprocess.run(["mdir", "-b", "-i", fat, "::" + path], capture_output=True, text=True, env=env)
                check(r.returncode == 0, "%s (PE6 %s)" % (path, lvl))

    print("7. u-boot environment vs fw_env.config")
    if 2 in p and cfg:
        text = open(cfg).read()
        es = re.search(r"^CONFIG_ENV_SIZE=(0x[0-9a-fA-F]+)", text, re.M)
        ef = re.search(r'^CONFIG_ENV_FAT_FILE="([^"]+)"', text, re.M)
        check("CONFIG_ENV_IS_IN_FAT=y" in text, "u-boot keeps its environment in FAT")
        check("CONFIG_ENV_REDUNDANT=y" not in text and "CONFIG_SYS_REDUNDAND_ENVIRONMENT=y" not in text,
              "single (not redundant) environment, as fw_env.config assumes")
        r = subprocess.run(["debugfs", "-R", "cat /etc/fw_env.config", "%s?offset=%d" % (img, p[2]["start"])],
                           capture_output=True, text=True)
        line = [l for l in r.stdout.splitlines() if l.strip() and not l.startswith("#")]
        check(len(line) == 1, "fw_env.config has one entry: %s" % (line[0] if line else "(none)"))
        if line and es and ef:
            f = line[0].split()
            check(f[0] == "/boot/" + ef.group(1), "file %s == /boot/%s" % (f[0], ef.group(1)))
            check(int(f[2], 16) == int(es.group(1), 16), "size %s == CONFIG_ENV_SIZE %s" % (f[2], es.group(1)))
    else:
        print("  info  skipped (needs UBOOT_BIN with its .config)")

    print("8. bootloader licence notices")
    if 2 in p:
        r = subprocess.run(["debugfs", "-R", "cat /usr/share/doc/reduxos-bootloader/NOTICES.txt",
                            "%s?offset=%d" % (img, p[2]["start"])], capture_output=True, text=True)
        check("Trusted Firmware-A (BL31)" in r.stdout and "U-Boot (SPL and u-boot proper)" in r.stdout,
              "/usr/share/doc/reduxos-bootloader/NOTICES.txt present (u-boot + TF-A sections)")

    print("RESULT: %s" % ("PASS" if not fails else "FAIL (%d)" % len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
