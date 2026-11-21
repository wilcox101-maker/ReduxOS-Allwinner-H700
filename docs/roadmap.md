# Roadmap

High-level direction. Status detail lives in [`status.md`](status.md); this is the shape of the work.

## Phase 0 — Foundation (now)
- [x] Repo scaffold: docs, provenance/clean-room, security baseline, CI, licence.
- [ ] Build pipeline populated: `image/build-image.sh`, `tools/build-retroarch.sh`, cores, QEMU smoke,
      hardening + licence checks (lifted and cleaned up from prior research work).
- [ ] First generated image boots in QEMU; CI build job enabled and green.

## Phase 1 — First light on hardware
- [ ] First boot on a real unit (per DRAM type), serial/console up.
- [ ] Panel bring-up confirmed per model (never drive an unidentified panel).
- [ ] GPU: Panfrost GLES confirmed on the Mali-G31; RetroArch renders.
- [ ] Per-unit first-boot: SSH host keys + machine-id + any PSK regenerated; firewall-on baseline confirmed.

## Phase 2 — Usable beta
- [ ] Input: both analog sticks merged to player 1; button/volume mapping.
- [ ] On-screen keyboard for non-RetroArch apps (KMS OSK).
- [ ] Core/system parity: games + BIOS folder layout, per-system playlists, ports framework.
- [ ] Power: suspend/resume, thermal within stock limits (never change the critical trip).

## Phase 3 — Polish & release
- [ ] Image size + boot time tuning.
- [ ] Per-model validation matrix filled in (`hardware.md`).
- [ ] Release images + reproducible build docs.

Dates are deliberately omitted — this is desk-first, hardware-gated work. See `status.md` for what's actually done.
