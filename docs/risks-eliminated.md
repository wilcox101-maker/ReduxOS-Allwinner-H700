# What a ground-up 24.04 build removes

Because ReduxOS is built from open Ubuntu 24.04 + upstream source and carries **nothing** from the stock
firmware, an entire class of stock risks and constraints simply does not exist here. Each row below is a
risk/constraint of typical stock Allwinner-H700 handheld firmware and ReduxOS's status. (Stock specifics are
described generically; exploit detail is kept out of this public repo on purpose.)

## Security risks — eliminated by design
| Stock risk | Why it was a risk | ReduxOS status |
|---|---|---|
| **Shared SSH host keys across all units** | identical identity on every device → trivial impersonation/MITM | **Gone** — keys generated per unit on first boot |
| **Shared default root password (same hash on every unit)** | one offline crack unlocks every device | **Gone** — no shipped root password; root login is key-only/opt-in or locked |
| **Remote root over SSH enabled at boot, password auth on** | open remote root surface | **Gone** — SSH off/opt-in; no password root login |
| **Firewall installed but inactive** | nothing actually filters inbound | **Fixed** — firewall enabled with an explicit allow policy |
| **Fixed factory Wi-Fi hotspot passphrase shared across units** | anyone nearby can join / the PSK is public | **Gone** — random per-unit PSK, generated only when the hotspot is used; modern cipher only |
| **DHCP/DNS server running at boot even without the hotspot** | LAN collision / unexpected service | **Fixed** — only runs with the hotspot |
| **Everything runs as root (launcher, apps, control scripts)** | any bug is a root bug | **Reduced** — unprivileged where practical; least-privilege services |
| **Root-owned code loaded/executed from the removable card** | anyone who writes the card runs code as root | **Gone** — no code executed as root from the card |
| **World-writable (0777) root paths and executables** | local tampering / privilege paths | **Gone** — sane permissions |
| **Unquoted user input into shell/`sed` in config scripts** | command injection as root | **Gone** — no such scripts carried; inputs quoted/validated |
| **No persistent journal** | nothing to diagnose after a fault | **Fixed** — persistent logging |
| **Bundled network-capable apps shipped and sometimes autostarted** | avoidable outbound/attack surface | **Gone** — none bundled; any networked app is opt-in and documented |
| **Y2038 / 32-bit `time_t` exposure in 32-bit stock userspace** | time rollover past 2038 | **Gone** — aarch64 + Noble's 64-bit `time_t` |

## Device-lock & vendor constraints — eliminated
| Stock constraint | ReduxOS status |
|---|---|
| **"deeplayer" anti-tamper device-lock** (reboots on mismatch; binds apps to the vendor kernel driver) | **Gone** — nothing depends on it; cores/apps built from source have no such check |
| **Vendor-locked binaries / blobs** you can't inspect or rebuild | **Gone** — everything builds from source |
| **Frozen vendor kernel** (old, no updates) | **Gone** — mainline-track kernel you control |

## Legal / IP constraints — eliminated (this is why it can be open)
| Stock constraint | ReduxOS status |
|---|---|
| **Redistributing vendor firmware / binaries** | **Not applicable** — none are included |
| **Bundled commercial/console BIOS or ROMs** | **Not applicable** — none are included; users supply their own legally |
| **Third-party emulator code with its own licence tangles** | **Not applicable** — ReduxOS ships only open cores built from source; in-house NDS work (ReduxDS) is a separate project, not bundled |
| **"Can we even share this?"** | **Resolved** — a from-scratch open build has no stock IP to encumber it |

## Still real (not removed by the base — ReduxOS must get these right itself)
- Panel/DRAM/WiFi variation per unit → identify before driving (never drive an unidentified panel).
- Ubuntu 24.04 trade-offs to manage: AppArmor's unprivileged-userns restriction (can affect sandboxed
  ports), frame pointers on by default (small RAM/size cost). See [`ubuntu-2404-notes.md`](ubuntu-2404-notes.md).
- Everything is **desk/QEMU** until validated on hardware.
