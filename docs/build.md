# Building ReduxOS — Allwinner H700

## Host requirements
`sudo tools/setup-build-host.sh` sets up an Ubuntu 24.04 x86_64 host (CI uses it): cross toolchain, image
tools, QEMU, the arm64 multiarch `-dev` packages and the aarch64 binfmt handler.

- An aarch64 build environment: native arm64, **or** x86_64 with `qemu-user-static` + `binfmt-support`.
- Tools: `debootstrap`/`mmdebstrap` or the project's apt-based rootfs builder, `genimage`/`mkfs`, `zstd`,
  `qemu-system-aarch64` (for the smoke test), build-essential + cross headers for source components.
- Disk: allow ~40 GB; each image build is several GB — delete finished `out/` dirs between builds.

## Steps
1. `image/packages.txt` — the Ubuntu 24.04 package manifest (the whole base; no stock rootfs).
   `image/rootfs/` is the ReduxOS configuration copied over it (services, firewall, SSH policy, RetroArch
   defaults, games-folder tools, OSK launchers).
2. `sudo [ENV...] ./image/build-image.sh [--ci] [--dram lpddr4|lpddr3]` — mmdebstrap rootfs, ReduxOS config,
   users, injected components, extlinux (u-boot-menu), genimage. Writes only under `$OUT` (default `./out`);
   it never touches a block device. `--help` lists every variable.
   - **QEMU / CI image:** `--ci` (= `KERNEL=ubuntu`, no bootloader). Ubuntu's generic arm64 kernel boots
     in QEMU only; it cannot boot an H700. Image name ends in `-ubuntu-qemu.img`.
   - **Device image:** `KERNEL_DEB=<ReduxOS H700 kernel .deb>` and `UBOOT_BIN=u-boot-<device>-<lpddr4|lpddr3>-<ver>.bin`
     (with its `-NOTICES.txt` and `.config` beside it); add `--dram lpddr4` or `--dram lpddr3` to assert the
     type. The DRAM type is part of the image name, a mismatch with the binary or its `.config` is an error
     (LPDDR3 settings put 1.2 V on 1.1 V LPDDR4), and `image/check-boot-layout.py` checks the result. Build
     one image per DRAM type. The kernel comes from `kernel/` (below); the u-boot binaries from `uboot/`.
3. Checks on the built tree (read-only, on the build host):
   `sudo ./image/check-hardening.sh ./out` (SECURITY.md baseline) and `sudo ./tools/check-licences.sh ./out`
   (every component maps to a PROVENANCE.md row; no stock, BIOS or ROM material).
4. `sudo ./image/qemu/smoke-test.sh ./out/<image>.img` — boots a copy in QEMU (`virt`, `-cpu cortex-a53`, 512 MB)
   and checks first boot, per-unit identity, SSH off, firewall, no shipped credential, `retroarch --features`
   on the A53, every core loading, and no desktop stack in RetroArch's load closure. ~25 min under TCG.
5. Writing to an SD card is manual and deliberate (see below) — the repo never writes a card for you.

## Kernel (`kernel/`)
`kernel/prepare-tree.sh` fetches torvalds/linux at the pinned commit, applies `kernel/patches/` and the base
layer (`kernel/upstream/base-layer.txt`: upstream patchwork series by reference, checked by `git patch-id`),
copies `kernel/dts/` in, and runs the desk checks (DTB schema check, W=1 build of touched files, checkpatch).
`kernel/build-kernel.sh --build` then configures (arm64 defconfig, other platforms off,
`kernel/config/rg34xxsp.config`, module allowlist), checks that every fragment line holds, that the boot path
(SD slot 1, serial console) is built in, and that every enabled DT node has its driver, then builds
`linux-image-<ver>-rg34xxsp_*.deb` into `$WORK/kernel-out/` (`KERNEL_DEB=`). Needs `bison flex bc libssl-dev
device-tree-compiler dpkg-dev fakeroot rsync kmod cpio debhelper libdw-dev libelf-dev` (+ `dtschema` for the
schema check). No display yet: the panel needs the display layer and an owner-generated panel file
(PROVENANCE.md, category C).

## Injected-at-build (never committed)
Large or source-built artifacts are produced by `tools/` scripts and injected via env vars (e.g.
`RETROARCH_DEB=`, `CORES_DIR=`), so no binaries live in the repo. See each script's header.

- `tools/build-retroarch.sh [OUTDIR]` — upstream RetroArch `v1.22.2` (pinned commit, verified after fetch),
  cross-built for KMS/EGL/GLES 3.1 + udev + ALSA + FFmpeg only: no Qt, X11, Wayland, PulseAudio, JACK, SDL or
  Vulkan, no buildbot core downloads. It fails if a desktop library is linked, then packages
  `reduxos-retroarch_1.22.2-1reduxos1_arm64.deb` (Depends derived from the binary). Inject with
  `RETROARCH_DEB=`. Host: Ubuntu 24.04 x86_64 with `gcc/g++-aarch64-linux-gnu` and the arm64 multiarch `-dev`
  packages listed in the script header (~10 min on 2 CPUs).
- `tools/build-libretro-cores.sh [-o OUTDIR] [--include-nc] [core ...]` — the cores in `tools/cores.tsv`, each
  pinned to a full upstream commit (verified after fetch), cross-built and checked (aarch64, libretro API, GL
  linkage); writes `BUILD-SUMMARY.tsv`, `SHA256SUMS` and each core's upstream licence files. Resumable; one
  failing core does not stop the rest. Cores with a **non-commercial** licence are skipped unless
  `--include-nc` (private builds only — such an image is not a publishable release). ~1.5 h on 2 CPUs.
- `tools/build-redux-exec-core.sh OUTDIR` — the ReduxOS launcher core (runs ports/apps from playlists); put it
  in the same OUTDIR and inject with `CORES_DIR=`.
- `tools/build-osk-pointer.sh OUTDIR` — the fly-out OSK's gamepad→pointer bridge; `OSK_POINTER=`.
- `tools/fetch-portmaster.sh OUTDIR` — PortMaster at a pinned release, SHA-256 checked; `PORTMASTER_ZIP=`.

## Reproducibility
Pin every upstream (tag + commit/sha256). Record versions in [`../PROVENANCE.md`](../PROVENANCE.md). CI builds
the image on every PR.

## First boot and admin access
No credential ships in the image: root, `player` and `redux` all have locked passwords, no SSH key is
installed, and SSH is **off**. On first boot each unit generates its own SSH host keys and `/etc/machine-id`
and grows the root partition to the card.

- `player` (unprivileged, no sudo) is logged in on the console and runs RetroArch.
- `redux` is the admin account (sudo, key-only). To use it, put your SSH **public** key(s) in
  `reduxos/authorized_keys` on the card's FAT `BOOT` partition before the first boot. First boot installs them
  for `redux`, turns SSH on (key-only; no password login for anyone, root included) and deletes the file
  from `BOOT`. The file is read as data only; nothing on the card is executed.
- Without that file there is no remote login at all; the console shell (as `player`) still works.

## Writing to a card (manual)
> **Destructive — double-check the device node.** `zstdcat out/<image>.img.zst | sudo dd of=/dev/sdX bs=4M
> status=progress conv=fsync` (replace `/dev/sdX` with your card). Nothing in this repo writes a card
> automatically.

## Status
CI builds a `--ci` image on every PR (source-built RetroArch, launcher core, OSK pointer, PortMaster injected),
runs the hardening and licence checks and the QEMU smoke test. Desk/QEMU only — see [`status.md`](status.md).
