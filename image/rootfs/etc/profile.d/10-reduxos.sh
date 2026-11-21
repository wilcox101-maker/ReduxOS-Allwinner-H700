# SPDX-License-Identifier: GPL-2.0-only
# ReduxOS shell environment. Sourced by all login shells.
[ -n "$PS1" ] || return 0
export EDITOR=nano PAGER=less
# Clear prompt showing user@host and cwd; red when root.
if [ "$(id -u)" = 0 ]; then PS1='\[\e[1;31m\]\u@\h\[\e[0m\]:\w# '; else PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\w\$ '; fi
alias ll='ls -lh --color=auto'
alias ip='ip --color=auto'
redux-help() {
    echo "ReduxOS shell — RG34XX-SP"
    echo "  IP(s):     $(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2": "$4}' | paste -sd' ' || echo 'no network')"
    echo "  Admin:     'redux' (sudo, SSH key only) — provision a key on the BOOT partition; see README."
    echo "  Keyboard:  pair one with 'bluetoothctl' (scan on / pair / connect), or attach USB."
    echo "  Frontend:  'retroarch' to relaunch the game UI; run on the console (tty1)."
    echo "  Shells:    tmux for split/detachable sessions."
}
