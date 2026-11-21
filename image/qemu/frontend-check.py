#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
# In-guest frontend check (QEMU, -cpu cortex-a53), run by guest-check. Prints one "== fe:" summary line plus
# "== fe-fail:" lines. Checks, on the emulated A53: every installed libretro core loads (all libraries
# resolve) and answers the libretro API; the redux_exec launcher core writes its request file; the
# playlist scanner writes valid playlists; the ReduxOS services, /roms ownership, the ports link and uinput.
# Loading a core is not playing a game: speed and rendering need the real device.
import ctypes, glob, json, os, pwd, grp, subprocess, sys, tempfile

LIB = "/usr/lib/aarch64-linux-gnu/libretro"

class SysInfo(ctypes.Structure):
    _fields_ = [("library_name", ctypes.c_char_p), ("library_version", ctypes.c_char_p),
                ("valid_extensions", ctypes.c_char_p), ("need_fullpath", ctypes.c_bool),
                ("block_extract", ctypes.c_bool)]

class GameInfo(ctypes.Structure):
    _fields_ = [("path", ctypes.c_char_p), ("data", ctypes.c_void_p), ("size", ctypes.c_size_t),
                ("meta", ctypes.c_char_p)]

ENV = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_uint, ctypes.c_void_p)

def probe(so):  # child process: load one core and query it
    lib = ctypes.CDLL(so, mode=os.RTLD_NOW)
    lib.retro_api_version.restype = ctypes.c_uint
    assert lib.retro_api_version() == 1, "api version"
    si = SysInfo(); lib.retro_get_system_info(ctypes.byref(si))
    print((si.library_name or b"?").decode(errors="replace"))

def exec_core():  # child process: the launcher core must write the request and ask for shutdown
    rt = tempfile.mkdtemp(); os.environ["XDG_RUNTIME_DIR"] = rt
    target = os.path.join(rt, "Some Port.sh"); open(target, "w").write("true\n")
    lib = ctypes.CDLL(os.path.join(LIB, "redux_exec_libretro.so"), mode=os.RTLD_NOW)
    seen = []
    cb = ENV(lambda cmd, data: (seen.append(cmd), True)[1])
    lib.retro_set_environment(cb)
    lib.retro_load_game.restype = ctypes.c_bool
    ok = lib.retro_load_game(ctypes.byref(GameInfo(target.encode(), None, 0, None)))
    req = open(os.path.join(rt, "redux-exec.request")).read().strip()
    assert ok and req == target and 7 in seen, f"ok={ok} req={req!r} cmds={seen}"  # 7 = SHUTDOWN
    print("ok")

if len(sys.argv) == 3 and sys.argv[1] == "--probe":
    probe(sys.argv[2]); sys.exit(0)
if len(sys.argv) == 2 and sys.argv[1] == "--exec":
    exec_core(); sys.exit(0)

def run(*a):
    p = subprocess.run([sys.executable, __file__, *a], capture_output=True, text=True, timeout=300)
    out = (p.stdout if p.returncode == 0 else (p.stderr or p.stdout)).strip().splitlines()
    return p.returncode, (out[-1] if out else f"rc={p.returncode}")

fails, ok = [], 0
cores = sorted(glob.glob(f"{LIB}/*_libretro.so"))
for so in cores:
    rc, msg = run("--probe", so)
    if rc == 0: ok += 1
    else: fails.append(f"core {os.path.basename(so)}: {msg[:120]}")

ex = "absent"
if os.path.exists(f"{LIB}/redux_exec_libretro.so"):
    rc, msg = run("--exec"); ex = "ok" if rc == 0 else "FAIL"
    if rc: fails.append(f"redux_exec: {msg[:160]}")

# playlist scanner on a throwaway tree (MD -> picodrive, PORTS -> redux_exec)
scan = "skipped"
with tempfile.TemporaryDirectory() as t:
    for d, f in (("MD", "Test Game.md"), ("PORTS", "Test Port.sh"), ("GB", "x.gb")):
        os.makedirs(f"{t}/roms/{d}", exist_ok=True); open(f"{t}/roms/{d}/{f}", "w").close()
    p = subprocess.run(["/usr/local/bin/redux-scan-roms", f"{t}/roms", f"{t}/pl"], capture_output=True, text=True)
    lists = sorted(glob.glob(f"{t}/pl/*.lpl"))
    try:
        items = sum(len(json.load(open(l))["items"]) for l in lists); scan = f"{len(lists)}lists/{items}items"
    except Exception as e:
        scan = "FAIL"; fails.append(f"scan: {e}")

def owner(path):
    try: st = os.lstat(path); return f"{pwd.getpwuid(st.st_uid).pw_name}:{grp.getgrgid(st.st_gid).gr_name}"
    except Exception: return "missing"

svc = ",".join(subprocess.run(["systemctl", "is-active", s], capture_output=True, text=True).stdout.strip()
               for s in ("reduxos-roms-setup", "reduxos-playlists"))
ports = "link" if os.path.islink("/roms/ports") and os.path.realpath("/roms/ports") == "/roms/PORTS" else "missing"
pm = "absent"
if os.path.isdir("/opt/tools/PortMaster"):
    pm = owner("/opt/tools/PortMaster") + ("+hooks" if os.path.exists("/opt/tools/PortMaster/reduxos/launch_hooks.txt") else "-nohooks")
print(f"== fe: cores={len(cores)} load_ok={ok} load_fail={len(cores)-ok} exec={ex} scan={scan} svc={svc} "
      f"ports={ports} saves={owner('/roms/saves')} portmaster={pm} uinput={owner('/dev/uinput')}")
for f in fails: print(f"== fe-fail: {f}")
