# SPDX-License-Identifier: GPL-2.0-only
# ReduxOS player session. Runs only on the physical console (tty1); an SSH or other login just
# gets a shell. RetroArch drives KMS/GBM directly (no desktop). On exit, drop to a shell so the
# device is recoverable rather than looping.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$RETROARCH_RUNNING" ]; then
    export RETROARCH_RUNNING=1
    # Quiet the console cursor/blanking while the frontend owns the screen.
    setterm -cursor off 2>/dev/null || true
    # Launcher loop: picking a port/app in RetroArch loads the redux_exec core, which writes the
    # script path to a request file and closes RetroArch; we run it, then bring RetroArch back.
    REQ="${XDG_RUNTIME_DIR:-/tmp}/redux-exec.request"; [ -n "${XDG_RUNTIME_DIR:-}" ] || REQ="/tmp/redux-exec-$(id -u).request"
    while :; do
        rm -f "$REQ"
        retroarch --verbose 2>> "$HOME/retroarch-boot.log"
        [ -s "$REQ" ] || break
        target=$(head -n1 "$REQ"); rm -f "$REQ"
        redux-launch "$target" || true
    done
    setterm -cursor on 2>/dev/null || true
    # RetroArch exited. On a keyboardless handheld a bare console prompt is unusable, so bring up the
    # fly-out OSK terminal (gamepad-driven) if the graphics stack is there; fall back to a plain shell.
    clear 2>/dev/null || true
    echo "RetroArch closed."
    if command -v redux-shell >/dev/null 2>&1 && [ -e /dev/dri/card0 ]; then
        echo "Opening the on-screen-keyboard shell (left stick = pointer, A = click)..."
        redux-shell || true
    fi
    echo "ReduxOS console shell (player)."
    type redux-help >/dev/null 2>&1 && redux-help
    echo
    echo "Commands: 'retroarch' (game UI) · 'redux-shell' (OSK terminal) · 'redux-files' (OSK file mgr)"
    echo "(No keyboard? the OSK is gamepad-driven; or pair Bluetooth/USB, or SSH in as redux with your provisioned key.)"
fi
