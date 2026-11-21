# Hardware — Allwinner H700 family (Anbernic handhelds)

**SoC:** Allwinner **H700** — 4× ARM Cortex-A53, Mali-G31 (Bifrost) GPU.

| Trait | Notes |
|---|---|
| Architecture | aarch64 (arm64) userspace |
| DRAM | varies per unit (e.g. 1 GB / 2 GB LPDDR4; some LPDDR3) — build per DRAM type |
| GPU | Mali-G31 → Mesa **Panfrost**, KMS/GLES (no Vulkan yet on Bifrost v7) |
| Display | panel varies per model — **identify before driving; never drive an unidentified panel** |
| WiFi/BT | module varies per unit |
| Storage | microSD (boot + data); image is written to card as a separate, deliberate step |

List each validated unit here as it is confirmed (model, DRAM, panel, WiFi module, status).

**Device safety rules:** never undervolt below stock; never change the thermal critical trip; desk-only until
a unit is confirmed.

## Units (validated status)
| Model | DRAM | Panel | WiFi | Status |
|---|---|---|---|---|
| RG34XX-SP | _tbd_ | _tbd_ | _tbd_ | not yet validated |
| _add rows as units are confirmed_ | | | | |
