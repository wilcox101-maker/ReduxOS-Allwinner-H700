# Status

**Stage:** desk / QEMU. **Nothing has run on a physical H700 device yet.**
Every claim in this repo is tagged by evidence: `[D]` config/file, `[G]` static/disassembly, `[S]` source,
`[V]` device-verified. There are currently **no `[V]`** items — treat all behaviour as unverified on hardware.

## Milestones
- [ ] Build pipeline populated (`image/build-image.sh`, `tools/build-retroarch.sh`, cores, QEMU smoke)
- [ ] First QEMU boot of a generated image, green CI
- [ ] First boot on a real unit (per DRAM type)
- [ ] Panel bring-up confirmed per model
- [ ] GPU (Panfrost GLES) confirmed on Mali-G31
- [ ] First-boot per-unit key/PSK/machine-id regeneration confirmed
- [ ] Firewall-enabled baseline confirmed

## Notes
The build tooling is being brought in from a prior research line (mainline kernel, boot chain, RetroArch
KMS/GLES frontend). Until `image/build-image.sh` is populated, the build job in CI is skipped.
