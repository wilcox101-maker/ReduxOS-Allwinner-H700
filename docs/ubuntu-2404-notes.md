# Ubuntu 24.04 (Noble) base — notes & trade-offs for ReduxOS

Why 24.04, and what to manage on this hardware. Version strings are the release baseline; confirm the exact
point-release on the image you build.

## Why Noble over Jammy on the H700
- **Graphics (the main win):** Noble ships **Mesa 24.x** → materially more mature **Panfrost** for the
  **Mali-G31 (Bifrost)**: better GLES 3.1 conformance and shader-compiler fixes than Jammy's 22.0. Directly
  helps the RetroArch KMS/GLES frontend and GL libretro cores. (No Vulkan to rely on — Bifrost v7 `panvk` is
  not conformant in this era.)
- **Toolchain/libc:** glibc 2.39 + GCC 13 (gcc-14 available) → better Cortex-A53 codegen for source-built
  cores/frontend (pair with `-mcpu=cortex-a53` + LTO for the real gains).
- **Security baseline:** systemd 255, OpenSSL 3.0.x line, newer AppArmor — a cleaner starting point to harden
  from than Jammy.
- **Y2038:** aarch64 + Noble's 64-bit `time_t` — the 32-bit-`time_t`/2038 exposure of 32-bit stock userspace
  is simply absent.

## Trade-offs to manage deliberately
- **AppArmor unprivileged user-namespace restriction (new in 24.04).** Can break sandboxed apps / ports /
  `bwrap`-style sandboxes. Decide the device policy explicitly (profile the app, or set
  `kernel.apparmor_restrict_unprivileged_userns=0`) rather than inheriting the default silently.
- **Frame pointers enabled by default on 64-bit (new in 24.04).** Better profiling, at ~1–2 % runtime and a
  small code-size/RAM cost in every distro-built binary. On a RAM-constrained handheld, consider rebuilding
  hot packages (Mesa, RetroArch, cores) with `-fomit-frame-pointer` if it matters.
- **Mesa pulls LLVM (large).** Ubuntu's Mesa hard-links `libLLVM` (~133 MB on disk; ~7.5 MB RW per GL
  process). Panfrost itself doesn't need LLVM, but shedding it means maintaining a Mesa fork (`-Dllvm=disabled`)
  and tracking its security updates. Keep Ubuntu's Mesa for now; revisit for lower-RAM variants.
- **Size trends larger** (glibc, Mesa+LLVM, frame pointers). Keep the image small by building the frontend
  from source without Qt/X11/Wayland, using an asset shim, pinning cores, and shipping no `snapd`.

## Kernel note
ReduxOS runs its **own** mainline-track kernel, so Ubuntu's distro kernel version matters mainly for the
QEMU/CI path; the userspace GL/libc stack is what reaches the device.

### References
- Ubuntu 24.04 LTS release notes (discourse.ubuntu.com / documentation.ubuntu.com).
- Canonical, "Bringing 12-year LTS to 32-bit Arm…" (armhf 64-bit `time_t`).
