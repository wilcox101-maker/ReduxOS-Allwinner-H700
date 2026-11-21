#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# fetch-portmaster.sh — fetch the pinned PortMaster release (PortsMaster/PortMaster-GUI, MIT) and check
# its SHA-256 against the pin below (tag + commit + archive hash, recorded in PROVENANCE.md).
# Not committed (it carries prebuilt helper binaries); injected at image build with
#   sudo PORTMASTER_ZIP=<OUTDIR>/PortMaster.zip image/build-image.sh ...
# PortMaster updates itself on the device afterwards (over Wi-Fi), like on other handheld OSes.
# usage: tools/fetch-portmaster.sh [OUTDIR]   (default ./out-portmaster)
set -euo pipefail
TAG=2026.11.17-0700
TAG_COMMIT=872aadd8ecf1bc08c07968f5a173527a3ec18036   # refs/tags/2026.11.17-0700 (informational)
SHA=d96a921ed3110f3c1b56b1f5b88d34539241723bd2fb003f29edbce5402a4fef
OUT=${1:-$PWD/out-portmaster}; mkdir -p "$OUT"; OUT=$(readlink -f "$OUT")
curl -fsSL -o "$OUT/PortMaster.zip.part" \
  "https://github.com/PortsMaster/PortMaster-GUI/releases/download/$TAG/PortMaster.zip"
echo "$SHA  $OUT/PortMaster.zip.part" | sha256sum -c --quiet || { echo "PortMaster.zip: checksum mismatch" >&2; exit 1; }
mv "$OUT/PortMaster.zip.part" "$OUT/PortMaster.zip"; printf "%s %s\n" "$TAG" "$TAG_COMMIT" > "$OUT/PortMaster.tag"
echo "PortMaster $TAG: $OUT/PortMaster.zip"
