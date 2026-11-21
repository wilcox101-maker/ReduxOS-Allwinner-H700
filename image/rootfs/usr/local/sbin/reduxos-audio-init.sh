#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ReduxOS boot-time mixer baseline for the analog codec (card id "Codec", mainline control names).
# DESK ONLY: these starting levels/routing are from the mainline control names, not yet tuned on
# hardware. Each set is best-effort (|| true) so a renamed/absent control never blocks boot.
# Headphone-vs-speaker is handled by the kernel jack (hp-det PI3); we just enable both paths.
C=Codec
s() { amixer -c "$C" -q sset "$@" 2>/dev/null || true; }
# Output enable + levels
s 'Line Out' 80% unmute
s 'DAC' 80%
# Mono speaker amp pin and stereo line routing
s 'Speaker' unmute
s 'Line Out Source' 'Stereo'
# Software master (asound.conf softvol) to full; volume keys take it from here
amixer -q sset 'PCM' 100% 2>/dev/null || true
# Persist whatever the controls now read, so alsa-restore keeps it across reboots
alsactl -f /var/lib/alsa/asound.state store "$C" 2>/dev/null || true
exit 0
