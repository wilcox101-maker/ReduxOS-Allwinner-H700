# Provenance & clean-room statement

ReduxOS — Allwinner H700 is assembled entirely from:
1. **Ubuntu 24.04 LTS (Noble) packages** pulled from the official Ubuntu archive at build time, and
2. **Upstream open-source** built from source by the scripts in this repo (`tools/`, `image/`),

plus original configuration and scripts authored here.

**Not present in this repository or its output image:**
- Vendor (Anbernic) stock firmware, rootfs, `appfs`, kernel, device trees, or any vendor binary/blob.
- Any commercial or console BIOS, ROM, or copyrighted game asset.
- The stock "deeplayer" device-lock or any code derived from it.
- Any third-party emulator source code. Original in-house emulator work (e.g. the NDS project "ReduxDS")
  lives in its own separate repository and is not bundled here.

Each third-party component keeps its own upstream licence; this file tracks them for the aggregate image.
If you believe anything here is mis-attributed, open an issue.

| Component | Upstream source | Licence | How it enters the image |
|---|---|---|---|
| Ubuntu base userspace | Ubuntu 24.04 archive (`noble`, `-updates`, `-security`; main + universe) | (per package; `/usr/share/doc/<pkg>/copyright`) | `image/packages.txt` via mmdebstrap/apt |
| Ubuntu QEMU kernel | Ubuntu `linux-image-<ver>-generic` (QEMU/CI images only; cannot boot an H700) | GPL-2.0 | `KERNEL=ubuntu` / `--ci` |
| Linux kernel (H700) | kernel.org mainline + ReduxOS H700 config/device tree (not yet in this repo) | GPL-2.0 | injected `KERNEL_DEB=` |
| U-Boot (H700 SPL + u-boot) | u-boot.org (not yet in this repo); one build per DRAM type (LPDDR4 / LPDDR3) | GPL-2.0+ (notices shipped as `/usr/share/doc/reduxos-bootloader/NOTICES.txt`) | injected `UBOOT_BIN=` |
| ReduxOS scripts + config | this repository (`image/rootfs/`, `image/portmaster/`) | GPL-2.0-only (per-file SPDX) | `image/build-image.sh` |
| Mesa (Panfrost) | mesa3d.org via Ubuntu `libgl1-mesa-dri` / `libgles2` | MIT | Ubuntu package |
| RetroArch | github.com/libretro/RetroArch (pinned tag) | GPL-3.0 | `tools/build-retroarch.sh` |
| libretro cores | per-core upstream (pinned) | (per core) | `tools/build-cores.sh` |
| _add rows as components are added_ | | | |

ReduxOS is an independent project and is **not** affiliated with or endorsed by Allwinner, Anbernic, or
Canonical/Ubuntu. "Ubuntu" is a trademark of Canonical Ltd.; used here descriptively to identify the base.
