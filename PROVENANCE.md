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

`tools/check-licences.sh` enforces this file against every built image: each source-built or injected
component must have a row below (first column = its name), with the pin it was built at.

## Components

| Component | Upstream source (pin) | Licence | How it enters the image |
|---|---|---|---|
| Ubuntu base userspace | Ubuntu 24.04 archive (`noble`, `-updates`, `-security`; main + universe) | (per package; `/usr/share/doc/<pkg>/copyright`) | `image/packages.txt` via mmdebstrap/apt |
| Mesa (Panfrost) | mesa3d.org via Ubuntu `libgl1-mesa-dri` / `libgles2` | MIT | Ubuntu package |
| Ubuntu QEMU kernel | Ubuntu `linux-image-<ver>-generic` (QEMU/CI images only; cannot boot an H700) | GPL-2.0 | `KERNEL=ubuntu` / `--ci` |
| Linux kernel (H700) | kernel.org mainline + ReduxOS H700 config/device tree (not yet in this repo) | GPL-2.0 | injected `KERNEL_DEB=` |
| U-Boot (H700 SPL + u-boot) | u-boot.org (not yet in this repo); per DRAM type (LPDDR4 / LPDDR3) | GPL-2.0+ (+ notices shipped as `/usr/share/doc/reduxos-bootloader/NOTICES.txt`) | injected `UBOOT_BIN=` |
| ReduxOS scripts + config | this repository (`image/rootfs/`, `image/portmaster/`, `tools/*.c`) | GPL-2.0-only (per-file SPDX) | `image/build-image.sh` |
| RetroArch | [libretro/RetroArch](https://github.com/libretro/RetroArch) tag `v1.22.2` = `69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576` | GPL-3.0-or-later | `tools/build-retroarch.sh` → injected `RETROARCH_DEB=` (`reduxos-retroarch`) |
| `redux_exec` | ReduxOS launcher core, `tools/redux-exec-core.c`; header `libretro.h` from [libretro/libretro-common](https://github.com/libretro/libretro-common) `52781c4a8b5aae19d858f4a2326c8f8308c70f54` (untagged; MIT) | GPL-2.0-only | `tools/build-redux-exec-core.sh` → `CORES_DIR=` |
| `redux-osk-pointer` | ReduxOS, `tools/redux-osk-pointer.c` | GPL-2.0-only | `tools/build-osk-pointer.sh` → `OSK_POINTER=` |
| PortMaster | [PortsMaster/PortMaster-GUI](https://github.com/PortsMaster/PortMaster-GUI) release `2026.11.17-0700` (tag commit `872aadd8ecf1bc08c07968f5a173527a3ec18036`), `PortMaster.zip` SHA-256 `d96a921ed3110f3c1b56b1f5b88d34539241723bd2fb003f29edbce5402a4fef` | MIT (bundles third-party helpers under their own licences) | `tools/fetch-portmaster.sh` → `PORTMASTER_ZIP=` |
| libretro cores (packaged) | Ubuntu `libretro-*` packages listed in `image/packages.txt` | (per package) | Ubuntu package |

## Source-built libretro cores

Pinned in [`tools/cores.tsv`](tools/cores.tsv) to full upstream commit SHAs (none of these upstreams tags the
pinned commit). Built by `tools/build-libretro-cores.sh` and injected with `CORES_DIR=`; each core's upstream
licence files ship in `/usr/share/doc/reduxos-cores/<core>/`. Cores marked **private only** carry a
non-commercial licence: they are skipped unless `--include-nc` is given, and an image that contains one may
not be published as a ReduxOS release (`check-licences.sh` fails unless `ALLOW_NC=1`).

| Core | Upstream | Commit | Licence | Distribution | Systems |
|---|---|---|---|---|---|
| `stella2014` | [libretro/stella2014-libretro](https://github.com/libretro/stella2014-libretro) | `7d1361e407e63f29e52892655069e5fb4096e691` | GPL-2.0 | public | A2600 |
| `a5200` | [libretro/a5200](https://github.com/libretro/a5200) | `40c6f2f1ad4a3145b328d5baaf010fae6c7e752b` | GPL-2.0 | public | A5200 |
| `prosystem` | [libretro/prosystem-libretro](https://github.com/libretro/prosystem-libretro) | `8a88014287c7a01cd568067e5a557d0a2b2a051f` | GPL-2.0 | public | A7800 |
| `atari800` | [libretro/libretro-atari800](https://github.com/libretro/libretro-atari800) | `4e7fbc73765c1a9670c7506616046ad1d4ccda51` | GPL-2.0 | public | A800 |
| `puae` | [libretro/libretro-uae](https://github.com/libretro/libretro-uae) | `d366f77c60e5a5f059f129cc3773d3048306083b` | GPL-2.0 | public | AMIGA |
| `vice_x64` | [libretro/vice-libretro](https://github.com/libretro/vice-libretro) | `76cde0b2cc4e52106618f2cc5d9d1112d9205c89` | GPL-2.0 | public | C64 |
| `vice_xvic` | [libretro/vice-libretro](https://github.com/libretro/vice-libretro) | `76cde0b2cc4e52106618f2cc5d9d1112d9205c89` | GPL-2.0 | public | VIC20 |
| `picodrive` | [libretro/picodrive](https://github.com/libretro/picodrive) | `1890c2932234c9d30f4cd3851d02228baae8f09e` | nc (MAME-style) | **private only** (`--include-nc`) | MD;MDCD;SMS;GG;SEGA32X |
| `gw` | [libretro/gw-libretro](https://github.com/libretro/gw-libretro) | `91d599b951e7bfe7e040347f58667cba20074adc` | Zlib | public | GW |
| `handy` | [libretro/libretro-handy](https://github.com/libretro/libretro-handy) | `bc55d462f0b2d6b073ea93dc552ebd73cec60fd1` | Zlib | public | LYNX |
| `race` | [libretro/RACE](https://github.com/libretro/RACE) | `c660d9ab5aafb47aefff90182ca90d319ad9b077` | GPL-2.0 | public | NGP |
| `pokemini` | [libretro/PokeMini](https://github.com/libretro/PokeMini) | `132111b76343559860532a1ccc094f93f1ed5650` | GPL-3.0 | public | POKE |
| `vecx` | [libretro/libretro-vecx](https://github.com/libretro/libretro-vecx) | `dccff5402a16d1ea7c112095a8e42632bf149506` | GPL-3.0 | public | VARCADE |
| `bluemsx` | [libretro/blueMSX-libretro](https://github.com/libretro/blueMSX-libretro) | `e3086eb5d36d77fa11704cf53dc176686e70127d` | nc (blueMSX) | **private only** (`--include-nc`) | MSX |
| `neocd` | [libretro/neocd_libretro](https://github.com/libretro/neocd_libretro) | `b1e04c738cb48a1dae0574b8877f6a116d270ca1` | LGPL-3.0 | public | NEOCD |
| `fake08` | [jtothebell/fake-08](https://github.com/jtothebell/fake-08) | `814991a2571ad3970e386cef48f3b148aa1c27b9` | MIT | public | PICO |
| `dosbox_pure` | [libretro/dosbox-pure](https://github.com/libretro/dosbox-pure) | `e39497e7c2a32c67c26e6598dd14f6d58c384bfd` | GPL-2.0 | public | DOS |
| `mupen64plus_next` | [libretro/mupen64plus-libretro-nx](https://github.com/libretro/mupen64plus-libretro-nx) | `15bada85906593376e8fd697f1b0b3af3a20f512` | GPL-2.0 | public | N64 |
| `mame2003_plus` | [libretro/mame2003-plus-libretro](https://github.com/libretro/mame2003-plus-libretro) | `2a60eda71ae0fea543a76a43b5d58086a5485256` | nc (MAME) | **private only** (`--include-nc`) | MAME |
| `fbneo` | [libretro/FBNeo](https://github.com/libretro/FBNeo) | `84b9ef052091b8c0885a479f444ae08bd840bc4c` | nc (FBNeo) | **private only** (`--include-nc`) | FBNEO;CPS1;CPS2;CPS3;NEOGEO |
| `flycast` | [flyinghead/flycast](https://github.com/flyinghead/flycast) | `6ab783f3be291894b9962523f381dd22b82f52d0` | GPL-2.0 | public | DREAMCAST;NAOMI |
| `ppsspp` | [hrydgard/ppsspp](https://github.com/hrydgard/ppsspp) | `77106069bf68fd80d4a7a5a519ae9d06b5677c4b` | GPL-2.0 | public | PSP |
| `pcsx_rearmed` | [libretro/pcsx_rearmed](https://github.com/libretro/pcsx_rearmed) | `7b0e8f8fadfbce3d170d195b9d9eecaabfa08c8e` | GPL-2.0 | public | PS |

ReduxOS is an independent project and is **not** affiliated with or endorsed by Allwinner, Anbernic, or
Canonical/Ubuntu. "Ubuntu" is a trademark of Canonical Ltd.; used here descriptively to identify the base.
