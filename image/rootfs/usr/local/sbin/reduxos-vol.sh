#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ReduxOS volume-key handler. Nudges the software master ("PCM" softvol in asound.conf) so
# the hardware routing set at boot is left intact. Called by triggerhappy on the volume keys.
case "$1" in
  up)   amixer -q sset 'PCM' 5%+ ;;
  down) amixer -q sset 'PCM' 5%- ;;
  *)    exit 1 ;;
esac
exit 0
