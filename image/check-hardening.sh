#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# check-hardening.sh — assert a built ReduxOS rootfs meets the security baseline in SECURITY.md and
# docs/risks-eliminated.md. Read-only; runs on the build host against the staged tree (no chroot).
# usage: image/check-hardening.sh <rootfs-dir | out-dir containing rootfs/>
# Exit 0 = every check passed; 1 = at least one failed (each failure printed).
set -u
R=${1:?usage: check-hardening.sh <rootfs-or-out-dir>}
[ -d "$R/rootfs/etc" ] && R=$R/rootfs
[ -f "$R/etc/passwd" ] || { echo "not a rootfs: $R" >&2; exit 2; }
R=$(cd "$R" && pwd)
FAIL=0
ok()  { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; FAIL=1; }
t()   { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
wants() { [ -L "$R/etc/systemd/system/$1/$2" ] || [ -e "$R/etc/systemd/system/$1/$2" ]; }
pkg() { grep -qE "^$1\s" "$R/root/manifest.tsv"; }
export R

echo "== per-unit credentials (nothing shared across units)"
t "no SSH host keys in the image (made per unit on first boot)" bash -c '! ls "$R"/etc/ssh/ssh_host_* >/dev/null 2>&1'
t "machine-id not set in the image (made per unit on first boot)" bash -c '[ ! -s "$R/etc/machine-id" ] || grep -qx uninitialized "$R/etc/machine-id"'
t "no D-Bus machine-id copy" test ! -s "$R/var/lib/dbus/machine-id"
t "first-boot unit enabled (host keys, owner key, growth)" wants sysinit.target.wants h700-firstboot.service
t "no shipped Wi-Fi network/PSK (iwd)" bash -c '! ls "$R"/var/lib/iwd/*.psk "$R"/var/lib/iwd/*.8021x >/dev/null 2>&1'
t "no shipped NetworkManager/wpa_supplicant secrets" bash -c '! ls "$R"/etc/NetworkManager/system-connections/* "$R"/etc/wpa_supplicant/*.conf >/dev/null 2>&1'
t "no hotspot/DHCP server enabled at boot (hostapd, dnsmasq)" bash -c '! ls "$R"/etc/systemd/system/*.wants/{hostapd,dnsmasq}.service >/dev/null 2>&1'

echo "== no shipped password or key"
for u in root player redux; do
	t "$u: password locked" bash -c "awk -F: -v u=$u '\$1==u && \$2 ~ /^[!*]/ {f=1} END {exit !f}' \"\$R/etc/shadow\""
done
t "no account has a usable password hash" bash -c "! awk -F: '\$2 !~ /^[!*]/ && \$2 != \"\" {print \$1}' \"\$R/etc/shadow\" | grep -q ."
t "no empty password field" bash -c "! awk -F: '\$2 == \"\" {print \$1}' \"\$R/etc/shadow\" | grep -q ."
t "no authorized_keys shipped for any user" bash -c '! find "$R/root" "$R/home" "$R/etc/ssh" -name "authorized_keys*" 2>/dev/null | grep -q .'
t "no private keys outside /etc/ssh host-key slots" bash -c '! grep -rlsE -- "-----BEGIN ([A-Z]+ )?PRIVATE KEY-----" "$R/etc" "$R/root" "$R/home" "$R/opt" "$R/usr/local" 2>/dev/null | grep -q .'

echo "== remote access off by default"
t "ssh.service not enabled" bash -c '! ls "$R"/etc/systemd/system/*.wants/ssh.service >/dev/null 2>&1'
t "ssh.socket not enabled" bash -c '! ls "$R"/etc/systemd/system/*.wants/ssh.socket >/dev/null 2>&1'
t "sshd: no password login" grep -qx 'PasswordAuthentication no' "$R/etc/ssh/sshd_config.d/60-reduxos.conf"
t "sshd: root never by password (prohibit-password)" grep -qx 'PermitRootLogin prohibit-password' "$R/etc/ssh/sshd_config.d/60-reduxos.conf"

echo "== firewall on"
t "nftables enabled at boot" wants sysinit.target.wants nftables.service
t "inbound policy drop" grep -q 'type filter hook input priority filter; policy drop;' "$R/etc/nftables.conf"
t "forward policy drop" grep -q 'type filter hook forward priority filter; policy drop;' "$R/etc/nftables.conf"

echo "== least privilege, no world-writable code"
t "player is not in sudo" bash -c "! awk -F: '/^sudo:/{print \$4}' \"\$R/etc/group\" | grep -qw player"
t "only redux has a sudoers rule" bash -c '! grep -rlsE "^[^#]*ALL" "$R"/etc/sudoers.d/ | grep -v 60-reduxos-admin | grep -q .'
ww=$(find "$R/usr" "$R/etc" "$R/opt" "$R/boot" -xdev \( -type f -o -type d \) -perm -0002 ! -perm -1000 2>/dev/null | sed "s|^$R||" | head -5)
t "no world-writable file or dir under /usr /etc /opt /boot" test -z "$ww"; [ -z "$ww" ] || echo "        $ww"
t "uinput only for the input group (0660)" grep -q 'GROUP="input", MODE="0660"' "$R/etc/udev/rules.d/70-reduxos-uinput.rules"
# No root service may execute anything from a card (/roms is the games card; /boot is FAT, owner-writable)
rc=$(grep -rhsE '^\s*Exec[A-Za-z]*=' "$R/etc/systemd/system" "$R/usr/lib/systemd/system" 2>/dev/null | grep -E '(/roms|/boot|/media|/mnt)/' | head -3)
t "no systemd unit executes code from /roms, /boot, /media or /mnt" test -z "$rc"; [ -z "$rc" ] || echo "        $rc"
t "launcher only accepts card scripts as the unprivileged player" grep -q '/roms/PORTS/\*|/roms/APPS/\*|/opt/tools/PortMaster/\*) ;;' "$R/usr/local/bin/redux-launch"
# uids are compared numerically: the host's user names are not the image's
t "PortMaster (if injected) owned by player, not root" bash -c '[ ! -d "$R/opt/tools/PortMaster" ] || [ "$(stat -c %u "$R/opt/tools/PortMaster")" = "$(awk -F: '"'"'$1=="player"{print $3}'"'"' "$R/etc/passwd")" ]'

echo "== no telemetry / unprompted network"
t "motd-news timer off" test ! -e "$R/etc/systemd/system/timers.target.wants/motd-news.timer"
t "no snapd, popularity-contest, ubuntu-report, whoopsie, apport" bash -c '! grep -qE "^(snapd|popularity-contest|ubuntu-report|whoopsie|apport)\s" "$R/root/manifest.tsv"'

echo "== no desktop stacks"
t "retroarch is the source-built reduxos-retroarch" pkg reduxos-retroarch
if pkg reduxos-retroarch; then
	need=$(readelf -d "$R/usr/bin/retroarch" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
	t "retroarch itself links no Qt/X11/xcb/Wayland/Pulse/JACK/SDL/Vulkan (direct NEEDED)" bash -c "[ -n '$need' ] && ! printf '%s\n' '$need' | grep -qE 'Qt[56]|libX11|libxcb|libwayland|libpulse|libjack|libSDL|libvulkan'"
	# the full load closure is checked in QEMU (image/qemu/smoke-test.sh): Ubuntu's FFmpeg pulls X11 client libs
fi
# xwayland is present: noble's cage (fly-out OSK compositor) hard-depends on it; it only starts if an X client
# connects to an OSK session. It is not linked into the frontend.
t "no Qt, X.Org server, desktop, sound-server or JACK daemon packages" bash -c '! grep -qE "^(libqt5[a-z0-9-]*|libqt6[a-z0-9-]*|xserver-xorg[a-z-]*|ubuntu-desktop[a-z-]*|gnome-shell|plasma-[a-z-]*|pulseaudio|pipewire|wireplumber|jackd2?)\s" "$R/root/manifest.tsv"'
t "no Vulkan drivers (mesa-vulkan-drivers)" bash -c '! grep -qE "^mesa-vulkan-drivers\s" "$R/root/manifest.tsv"'

echo "== logging"
t "journal kept across reboots" grep -qx 'Storage=persistent' "$R/etc/systemd/journald.conf.d/60-h700.conf"

echo "== no stock / vendor material"
t "no stock device-lock strings (deeplayer) in /usr /opt /etc" bash -c '! grep -rlqa -e deeplayer -e debug2_reg2 "$R/usr" "$R/opt" "$R/etc" 2>/dev/null'
t "no stock vendor apps (*.dge, dmenu.bin)" bash -c '! find "$R" -xdev \( -iname "*.dge" -o -iname "dmenu.bin" \) -print -quit | grep -q .'

[ "$FAIL" = 0 ] && echo "hardening check: PASS" || { echo "hardening check: FAIL"; exit 1; }
