# Roadmap: one finish line

**ReduxOS 1.0 = the ReduxOS image (this repo) + the Redux frontend, with every Redux Beta checklist passing on the
mainline kernel, on a real RG34XX-SP.** One finish line for three repos (Dale, Q12, 2026-11-21; overseer audit
P1–P3). Lead: the Redux Owner; coordination and merges: the Redux Manager; support: Deep Research (DR) and Kernel
Research (KR). Status detail: [`status.md`](status.md). Nothing is ticked until it has been checked on the device (`[V]` + build SHA).

## Where each part lives
| Repo | Role |
|---|---|
| **ReduxOS-Allwinner-H700** (this, public, GPL-3.0) | **The product:** image build, kernel/u-boot/TF-A build, packages, checks, releases |
| [Allwinner-H700-Custom-Kernel-Research](https://github.com/wilcox101-maker/Allwinner-H700-Custom-Kernel-Research) | **Research:** device tree, kernel patches, panel drivers, RE notes, device test kits and run sheets |
| [Anbernic_RG34XXSP_Redux](https://github.com/wilcox101-maker/Anbernic_RG34XXSP_Redux) | **The Redux frontend** (BIOS/DOS-style menu, settings, Engineering, OSK) and the stock-kernel Redux CFW line (Beta v0.5) |

## Stages (in order)
| # | Stage | Done when | Who |
|---|---|---|---|
| **S1** | **Release image built here** (desk) | Kernel + u-boot + TF-A builds ported from H700; LPDDR4 and LPDDR3 cards built by CI; QEMU smoke, hardening and licence checks green | DR builds, Owner reviews |
| **S2** | **First light** (bench session 1) | On Dale's 2 GB LPDDR4 unit: FEL/UART K3 (`DRAM: 2 GiB`) and K4 (panel strap PE6); the card boots; panel + backlight (K18/K19); Panfrost GLES + RetroArch draws a frame; per-unit keys and firewall live | KR/DR kit + run sheet, Manager pre-test audit, **Dale runs the device** |
| **S3** | **Hardware bring-up** (sessions 2+) | Sticks (K5/K7, R34), speaker amp + codec (K15), Wi-Fi/BT (K16), battery and charging (K14), lid wake, thermal inside stock limits, CPU table (K8, K21/K22) | Owner leads, KR/DR desk work |
| **S4** | **Redux frontend on ReduxOS** (Redux F7) | The R21 port: the frontend's 22 stock interfaces moved to mainline equivalents; F2–F6 checklists pass on this image; one OSK engine on this path | Owner |
| **S5** | **Release candidate** (Redux F8) | Install, update and rollback (R8); RG34XX-SP row of the hardware matrix; user docs; a week of daily use with no lost save; signed images from this repo | Owner, Manager, Dale signs off |

## Decisions this depends on (Dale)
| Item | Options | Owner's recommendation |
|---|---|---|
| **Image for first light (S2)** | H700 R33 slim LPDDR4 (ready, QEMU 20/20) now, or wait for S1 | **R33 now**, then repeat first light on the S1 image (S1 has no device risk to retire first) |
| **P1: what boots** | Redux menu first (RetroArch underneath for cores) or RetroArch first | **Redux menu first**: it is the definition of 1.0 above and carries the settings, Engineering and OSK work already device-checked on stock |
| **P2: Phase 2 base** | Ubuntu 24.04 (this repo) or the RAM-resident squashfs design | **Ubuntu 24.04** on record; the RAM-tier ideas (`r13`, `ram-system-design`) carried in as settings, not a second base |

## Alongside, not gating 1.0
- **Redux CFW Beta v0.5** stays as the stock-kernel line; its open device checks (OSK K24–K28, #259, #283/#284,
  Bluetooth, #149, #185) share bench sessions when time allows.
- **Out of scope for 1.0:** ReduxDS, HDMI, deep suspend, 512 MB / 1 GB tiers, Expert Mode, ZRAM (1.x).
