#!/usr/bin/env bash
# build-image.sh — assemble the ReduxOS rootfs + image from image/packages.txt (Ubuntu 24.04, aarch64).
#
# Writes only under $OUT. It NEVER touches a block device: writing the image to a card is a separate,
# deliberate, manual step (see docs/build.md).
#
# Injected at build, never committed (each from its tools/ script):
#   RETROARCH_DEB=<deb>  lean upstream RetroArch (tools/build-retroarch.sh)
#   CORES_DIR=<dir>      source-built *_libretro.so (tools/build-cores.sh)
#
# STATUS: stub. The build pipeline is being brought in from the prior research line
# (mainline kernel + boot chain + RetroArch KMS/GLES frontend). See docs/status.md.
set -euo pipefail

echo "build-image.sh is not yet implemented in this repository." >&2
echo "The pipeline (rootfs assembly, package install, image packing, QEMU smoke) is being populated;" >&2
echo "see docs/status.md and docs/build.md." >&2
exit 1
