# Status

**Stage:** desk / QEMU. **Nothing has run on a physical H700 device yet.**
Every claim in this repo is tagged by evidence: `[D]` config/file, `[G]` static/disassembly, `[S]` source,
`[V]` device-verified. There are currently **no `[V]`** items — treat all behaviour as unverified on hardware.

## Milestones
- [x] Build pipeline populated (`image/build-image.sh`, `tools/build-retroarch.sh`, cores, QEMU smoke) — desk
- [x] First QEMU boot of a generated image (`--ci` profile, Ubuntu QEMU kernel), green CI — desk/QEMU
- [ ] First boot on a real unit (per DRAM type)
- [ ] Panel bring-up confirmed per model
- [ ] GPU (Panfrost GLES) confirmed on Mali-G31
- [ ] First-boot per-unit key/PSK/machine-id regeneration confirmed
- [ ] Firewall-enabled baseline confirmed

## Notes
The build tooling was ported from a prior research line. Not yet here: the H700 kernel and u-boot build
scripts (device images need `KERNEL_DEB=` / `UBOOT_BIN=` injected), and the cores hatarib, yabasanshiro,
easyrpg and onscripter. CI runs the `--ci` profile (Ubuntu's generic kernel, QEMU only).

Known, desk-only findings:
- RetroArch links no desktop stack itself, but Ubuntu's FFmpeg brings X11/xcb **client** libraries into its
  load closure (no X server). Reported by the smoke test as info.
- noble's `cage` (fly-out OSK compositor) hard-depends on `xwayland`; it only starts if an X client connects.
