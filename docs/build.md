# Building ReduxOS — Allwinner H700

## Host requirements
- An aarch64 build environment: native arm64, **or** x86_64 with `qemu-user-static` + `binfmt-support`.
- Tools: `debootstrap`/`mmdebstrap` or the project's apt-based rootfs builder, `genimage`/`mkfs`, `zstd`,
  `qemu-system-aarch64` (for the smoke test), build-essential + cross headers for source components.
- Disk: allow ~40 GB; each image build is several GB — delete finished `out/` dirs between builds.

## Steps
1. `image/packages.txt` — the Ubuntu 24.04 package manifest (the whole base; no stock rootfs).
2. `sudo ./image/build-image.sh` — assembles the rootfs, installs packages, applies ReduxOS config, builds
   the image under `./out/`. Writes only under `$OUT`; it never touches a block device.
3. `./image/qemu/smoke-test.sh ./out/<image>` — boots in QEMU and runs the checks (boot, frontend present,
   hardening, no desktop stacks, licence check).
4. Writing to an SD card is manual and deliberate (see below) — the repo never writes a card for you.

## Injected-at-build (never committed)
Large or source-built artifacts are produced by `tools/` scripts and injected via env vars (e.g.
`RETROARCH_DEB=`, `CORES_DIR=`), so no binaries live in the repo. See each script's header.

## Reproducibility
Pin every upstream (tag + commit/sha256). Record versions in [`../PROVENANCE.md`](../PROVENANCE.md). CI builds
the image on every PR.

## Writing to a card (manual)
> **Destructive — double-check the device node.** `zstdcat out/<image>.img.zst | sudo dd of=/dev/sdX bs=4M
> status=progress conv=fsync` (replace `/dev/sdX` with your card). Nothing in this repo writes a card
> automatically.

## Status
Build pipeline scripts are being populated — see [`status.md`](status.md). `image/build-image.sh` is a stub
until the pipeline lands.
