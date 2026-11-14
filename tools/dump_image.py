"""Dumps default.xex's loaded image (0x82000000-0x82C50000) from a starting ironbrigade.exe.

ReXGlue maps guest virtual memory at host 0x100000000 (log: "Guest memory arena mapped"), so the
guest image is at 0x100000000 + 0x82000000. The image is loaded before any guest code runs; this
starts the game, waits for the log line "Function table initialized", reads the image, and kills
the process. Output: build/default.bin (the image from its base 0x82000000).

    python tools/dump_image.py [exe_dir]
"""
import ctypes
import ctypes.wintypes as wt
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
exe_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/IronBrigade"
BASE, END = 0x82000000, 0x82C50000
HOST = 0x100000000

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.OpenProcess.restype = wt.HANDLE
k32.ReadProcessMemory.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                  ctypes.POINTER(ctypes.c_size_t)]

logs = exe_dir / "logs"
before = set(logs.glob("*.log")) if logs.exists() else set()
p = subprocess.Popen([str(exe_dir / "ironbrigade.exe")], cwd=exe_dir)
try:
    deadline = time.time() + 30
    while time.time() < deadline:
        new = [f for f in logs.glob("*.log") if f not in before] if logs.exists() else []
        if new and "Function table initialized" in new[0].read_text(errors="replace"):
            break
        time.sleep(0.05)
    time.sleep(1.5)  # the log line comes before the image is copied in
    h = k32.OpenProcess(0x0010 | 0x0400, False, p.pid)  # VM_READ | QUERY_INFORMATION
    buf = ctypes.create_string_buffer(END - BASE)
    out = bytearray(END - BASE)
    page = 0x1000
    for off in range(0, END - BASE, page):
        n = ctypes.c_size_t()
        if k32.ReadProcessMemory(h, HOST + BASE + off, ctypes.byref(buf, off), page,
                                 ctypes.byref(n)):
            out[off:off + page] = buf.raw[off:off + page]
        elif off == 0x100000:
            print("read failed at", hex(BASE + off), "error", ctypes.get_last_error())
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "build/default.bin").write_bytes(out)
    print("dumped", hex(len(out)), "nonzero pages:",
          sum(1 for o in range(0, len(out), page) if any(out[o:o + page])))
finally:
    p.kill()
