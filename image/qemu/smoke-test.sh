#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# smoke-test.sh — boot a COPY of a built ReduxOS image under QEMU (aarch64 virt, -cpu cortex-a53, TCG) and
# fail unless the boot reached a healthy multi-user system that meets the ReduxOS baseline: frontend present,
# `retroarch --features` runs on the emulated A53 with KMS/EGL/GLES/udev/ALSA, every libretro core loads,
# no desktop stacks, per-unit identity, SSH off, firewall on, no shipped credential, persistent journal.
# The original image is not changed; nothing touches a card or block device.
#
# usage: sudo image/qemu/smoke-test.sh IMAGE.img [MB]      boot and check (MB default 512, the smallest tier)
#        image/qemu/smoke-test.sh --check-log LOG [KMODE]   only check an existing qemu-test.sh log
#   KMODE  deb (ReduxOS kernel) or ubuntu (QEMU-only kernel); taken from the image name.
# Writes <image>.smoke-<MB>.txt (and appends to $GITHUB_STEP_SUMMARY when set). Exit 0 = all checks passed.
# QEMU is not the H700: GPU rendering, panel, audio, input and speed need the device.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = --check-log ]; then
	LOG=${2:?--check-log LOG}; KMODE=${3:-deb}; REPORT=/dev/null
else
	[ -n "${1:-}" ] || { sed -n '2,12p' "$0"; exit 2; }
	IMG=$(readlink -f "$1"); MB=${2:-512}
	[ -f "$IMG" ] || { echo "no image: $1" >&2; exit 2; }
	case "$(basename "$IMG")" in *-ubuntu*.img) KMODE=ubuntu ;; *) KMODE=deb ;; esac
	"$HERE/qemu-test.sh" "$IMG" "$MB"
	LOG="${IMG%.img}.qemu-$MB.log"; REPORT="${IMG%.img}.smoke-$MB.txt"
fi
[ -f "$LOG" ] || { echo "no log: $LOG" >&2; exit 1; }

# guest-check lines arrive on the console as "[ time] guest-check[pid]: text"; keep the text only.
OUT=$(sed -n 's/^.*guest-check\[[0-9]*\]: //p' "$LOG" | tr -d '\r')
section() { printf '%s\n' "$OUT" | awk -v s="== $1" 'index($0, s) == 1 {on = 1; print; next} /^== |^GCEND/ {on = 0} on'; }
val() { printf '%s\n' "$OUT" | sed -n "s/^== $1: //p" | head -1; }

set +e   # every check runs; the exit status is decided at the end
PASS=0; FAIL=0; RESULTS=
check() {   # check <name> <ok:0/1> <detail>
	if [ "$2" = 0 ]; then PASS=$((PASS + 1)); RESULTS+="| PASS | $1 | $3 |"$'\n'
	else FAIL=$((FAIL + 1)); RESULTS+="| **FAIL** | $1 | $3 |"$'\n'; fi
}
has() { printf '%s\n' "$OUT" | grep -qE "$1"; }

# --- boot + first boot ---
has '^GCBEGIN$' && has '^GCEND$'; check "boot reached multi-user, check ran" $? "GCBEGIN/GCEND in the console log"
sys=$(val system); [ "$sys" = running ]; check "systemd state is running" $? "${sys:-none}"
fb=$(section firstboot | grep -o 'root grown: [0-9]* -> [0-9]* bytes' || true)
[ -n "$fb" ]; check "first boot grew the root filesystem" $? "${fb:-no 'root grown' line}"
root_gib=$(section disk | awk '$1 ~ /^\/dev\/root|^\/dev\/vda2/ {print $2}' | head -1)
[[ "$root_gib" =~ ^[2-9]\.?[0-9]*G$ ]]; check "root filesystem is ≥ 2 GiB after growth" $? "${root_gib:-?}"
has '^== apt: apt [0-9]'; check "apt installed" $? "$(val apt)"
svc=$(section services | sed -n 2p)
[ "$svc" = "active active active active active active" ]
check "networkd, iwd, earlyoom, resolved, zram, nftables active" $? "${svc:-none}"
section network | grep -qE '^ *[0-9]+ (eth0|en[a-z0-9]+) +ether +routable +configured'
check "wired network configured (routable)" $? "$(section network | grep -E 'eth0|en[a-z0-9]' | head -1 | tr -s ' ')"

# --- security baseline (SECURITY.md) ---
keys=$(val 'ssh host keys'); [ "${keys:-0}" -ge 3 ]; check "per-unit SSH host keys generated on first boot" $? "${keys:-0} keys"
mid=$(val machine-id); [[ "$mid" =~ ^[0-9a-f]{32}$ ]]; check "per-unit machine-id generated on first boot" $? "${mid:-none}"
fw=$(val firewall); [ "$fw" = "active 1" ]; check "firewall active, inbound policy drop" $? "${fw:-none}"
sshd=$(val sshd)
printf '%s' "$sshd" | grep -q 'listening=inactive,inactive' && printf '%s' "$sshd" | grep -q 'enabled=disabled'
check "SSH off by default (no owner key provisioned)" $? "$(printf '%s' "$sshd" | cut -d' ' -f1-2)"
printf '%s' "$sshd" | grep -q 'permitrootlogin without-password' && printf '%s' "$sshd" | grep -q 'passwordauthentication no'
check "sshd: no password login (root key-only)" $? "$(printf '%s' "$sshd" | cut -d' ' -f3-)"
cr=$(val creds); [ "$cr" = "root=L player=L redux=L keys=0" ]
check "no shipped credential (all passwords locked, no keys)" $? "${cr:-none}"
jn=$(val journal); [ "$jn" = persistent ]; check "persistent journal" $? "${jn:-none}"

# --- frontend ---
fe=$(val frontend)
printf '%s' "$fe" | grep -q 'player=yes' && printf '%s' "$fe" | grep -q 'ra=yes' && printf '%s' "$fe" | grep -qE 'cores=[1-9]'
check "frontend present (player, retroarch, cores)" $? "${fe:-none}"
printf '%s' "$fe" | grep -q 'autologin=autologin player'
check "tty1 autologins the unprivileged player" $? "$(printf '%s' "$fe" | grep -o 'autologin=[a-z ]*' || echo missing)"
raf=$(val ra-features)
ok=0; for f in KMS EGL OpenGLES UDEV ALSA; do printf '%s' "$raf" | grep -qiE "(^| )${f}[^ :]*:yes" || ok=1; done
check "retroarch --features on the A53: KMS/EGL/GLES/udev/ALSA" $ok "$(printf '%s' "$raf" | cut -c1-160)"
# (RetroArch's own NEEDED list is checked on the build host by image/check-hardening.sh)
clo=$(val ra-closure)
! printf '%s' "$clo" | grep -qE 'Qt[56]|wayland|pulse|jack|SDL|vulkan'
check "no Qt/Wayland/Pulse/JACK/SDL/Vulkan in RetroArch's load closure" $? "$(printf '%s' "$clo" | tr ' ' '\n' | grep -E 'Qt[56]|wayland|pulse|jack|SDL|vulkan' | paste -sd, || true)"
x11=$(printf '%s' "$clo" | tr ' ' '\n' | grep -cE 'libX|libxcb' || true)
RESULTS+="| info | X11 client libs in RetroArch's closure (via Ubuntu FFmpeg: libavutil -> libva-x11/libvdpau) | ${x11:-0}; no X server |"$'\n'
fec=$(val fe)
if printf '%s' "$fec" | grep -q 'cores='; then
	printf '%s' "$fec" | grep -q 'load_fail=0 ' && ! has '^== fe-fail:'
	check "every libretro core loads on the emulated A53" $? "${fec%% exec=*} $(printf '%s\n' "$OUT" | sed -n 's/^== fe-fail: //p' | head -3 | paste -sd';')"
	printf '%s' "$fec" | grep -qE 'exec=ok .*scan=[1-9]lists/[1-9]'
	check "launcher core + playlist scanner work" $? "$(printf '%s' "$fec" | grep -oE 'exec=[^ ]+ scan=[^ ]+')"
	printf '%s' "$fec" | grep -qE 'svc=active,active ports=link saves=player:player'
	check "games tree owned by player, ports link, ReduxOS services" $? "$(printf '%s' "$fec" | grep -oE 'svc=.*')"
else
	check "frontend core check ran" 1 "no '== fe:' line (python3 or frontend-check.py missing?)"
fi

# --- kernel + boot menu ---
kver=$(val kernel)
if [ "$KMODE" = deb ]; then [[ "$kver" != *-generic ]]; else [[ "$kver" == *-generic ]]; fi
check "kernel matches the image ($KMODE)" $? "${kver:-none}"
section extlinux | grep -qE '^\s*linux '; check "extlinux.conf written by u-boot-menu" $? \
	"$(section extlinux | grep -m1 -E '^\s*linux ' | tr -d '\t')"
bad=$(grep -E 'Kernel panic|Oops|BUG:|Call trace:|segfault' "$LOG" | head -3 || true)
[ -z "$bad" ]; check "no panic/oops/BUG/segfault in the log" $? "${bad:-none}"
# DNS through QEMU user networking depends on the host network: reported, not failed.
dns=$(section network | grep -c 'ports.ubuntu.com: [0-9]' || true)
RESULTS+="| info | DNS lookup of ports.ubuntu.com | $([ "$dns" -gt 0 ] && echo resolved || echo 'not resolved (host network)') |"$'\n'
avail=$(section mem | awk '/^Mem:/ {print $NF " MB available of " $2}')
RESULTS+="| info | memory | ${avail:-?} |"$'\n'

{
	echo "### ReduxOS QEMU smoke test: $PASS passed, $FAIL failed"
	echo
	echo "Log: \`$(basename "$LOG")\`. QEMU virt + Cortex-A53, TCG — desk only, not H700 hardware."
	echo
	echo "| Result | Check | Detail |"; echo "|---|---|---|"
	printf '%s' "$RESULTS"
} | tee "$REPORT" | { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then tee -a "$GITHUB_STEP_SUMMARY"; else cat; fi; }
[ "$FAIL" -eq 0 ]
