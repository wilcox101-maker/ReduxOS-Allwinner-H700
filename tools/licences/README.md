# Licence texts not shipped in u-boot's `Licenses/`

Used by `tools/bootloader_notices.py` when a file compiled into the bootloader carries an SPDX identifier whose text
u-boot does not include. Each file is the licence text exactly as published; do not edit.

| File | SPDX id | Source | Checked |
|---|---|---|---|
| `Unicode-DFS-2016.txt` | Unicode-DFS-2016 | SPDX license-list-data `text/Unicode-DFS-2016.txt`, byte-identical at tag `v3.29.0` and at `main` `31846481de7e` (git blob `71fd6ac5e12e`, SHA-256 `1a33fc12a3ab…`). The list data is CC0-1.0. | 2026-11-15 |

Why: u-boot's `include/capitalization.h` (compiled in through `CONFIG_EFI_UNICODE_CAPITALIZATION=y`, a defconfig
default) is tagged `Unicode-DFS-2016`; that licence requires its copyright and permission notice to appear with copies
or in associated documentation. Decision (Dale, 2026-11-14): ship the text in the notices, keep the option, no binary change.
