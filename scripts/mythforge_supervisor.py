"""Mythforge service supervisor — one process that IS the app's backend life.

The game exe launches this at boot; it starts every service Mythforge needs
(Ollama, Chroma, ComfyUI, the image bridge, the FastAPI backend) and — the
whole point — guarantees they DIE when the game closes, however it closes.

The guarantee is a Windows **Job Object** with KILL_ON_JOB_CLOSE: every service
we start is assigned to the job, and the moment this supervisor's handle to
that job is released (we exit, or we crash, or we are killed), Windows
terminates the entire job. No orphans, ever — that is the OS doing it, not us
hoping to.

We ALSO watch the game's PID and shut down cleanly when it exits, so closing
the game window tears the stack down in a couple of seconds.

Idempotent: a service already healthy is adopted, not restarted, and adopted
services are left running on shutdown (we only kill what we started). So this
is safe to run over a hand-started dev stack.

Usage (normally invoked by the game, but standalone-testable):
    python mythforge_supervisor.py --game-pid <PID>
    python mythforge_supervisor.py --up-only     # start + verify, don't watch
    python mythforge_supervisor.py --down         # stop a running supervisor
    python mythforge_supervisor.py --status
"""
from __future__ import annotations
import argparse
import ctypes
import json
import os
import subprocess
import sys
import time
import urllib.request
from ctypes import wintypes
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent          # Code/mythforge
SIB = REPO.parent                                       # Code/
STATE = REPO / ".supervisor.json"                       # pid + what we started
LOG = REPO / "logs" / "supervisor.log"

# ── Windows Job Object (the death-with-parent guarantee) ────────────────────
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
CREATE_NO_WINDOW = 0x08000000
CREATE_BREAKAWAY_FROM_JOB = 0x01000000


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", wintypes.LARGE_INTEGER),
        ("PerJobUserTimeLimit", wintypes.LARGE_INTEGER),
        ("LimitFlags", wintypes.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", wintypes.DWORD),
        ("Affinity", ctypes.POINTER(ctypes.c_ulong)),
        ("PriorityClass", wintypes.DWORD),
        ("SchedulingClass", wintypes.DWORD),
    ]


class IO_COUNTERS(ctypes.Structure):
    _fields_ = [("ReadOperationCount", ctypes.c_ulonglong),
                ("WriteOperationCount", ctypes.c_ulonglong),
                ("OtherOperationCount", ctypes.c_ulonglong),
                ("ReadTransferCount", ctypes.c_ulonglong),
                ("WriteTransferCount", ctypes.c_ulonglong),
                ("OtherTransferCount", ctypes.c_ulonglong)]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
                ("IoInfo", IO_COUNTERS),
                ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t)]


def make_kill_job():
    k32 = ctypes.windll.kernel32
    job = k32.CreateJobObjectW(None, None)
    info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    k32.SetInformationJobObject(job, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                                ctypes.byref(info), ctypes.sizeof(info))
    return job


def assign_to_job(job, pid):
    k32 = ctypes.windll.kernel32
    PROCESS_SET_QUOTA = 0x0100
    PROCESS_TERMINATE = 0x0001
    h = k32.OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, False, pid)
    if h:
        k32.AssignProcessToJobObject(job, h)
        k32.CloseHandle(h)


def pid_alive(pid):
    k32 = ctypes.windll.kernel32
    SYNCHRONIZE = 0x00100000
    h = k32.OpenProcess(SYNCHRONIZE, False, pid)
    if not h:
        return False
    # WAIT_TIMEOUT (0x102) => still running.
    alive = k32.WaitForSingleObject(h, 0) != 0
    k32.CloseHandle(h)
    return alive


# ── Health ──────────────────────────────────────────────────────────────────
def http_ok(url, timeout=3):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return 200 <= r.status < 500      # 401/403 = "up but guarded" = up
    except Exception as e:
        return getattr(e, "code", 0) in (401, 403)


def log(msg):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


# ── The service graph ─────────────────────────────────────────────────────
def comfy_dir():
    for c in (SIB / "ComfyUI-Zluda", SIB / "ComfyUI"):
        if c.exists():
            return c
    return None


def services():
    """Ordered by dependency. Each: name, health url, how to start, timeout.
    `optional` services never block the game (art can warm up behind play)."""
    venv_py = REPO / "venv" / "Scripts" / "python.exe"
    py = str(venv_py) if venv_py.exists() else sys.executable
    ollama = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Ollama" / "ollama.exe"
    cd = comfy_dir()
    svc = [
        {"name": "ollama", "url": "http://127.0.0.1:11434/api/tags", "timeout": 40,
         "cmd": [str(ollama) if ollama.exists() else "ollama", "serve"], "cwd": str(REPO),
         "optional": False},
        {"name": "chroma", "url": "http://127.0.0.1:8100/api/v2/heartbeat", "timeout": 60,
         "cmd": ["chroma", "run", "--host", "0.0.0.0", "--port", "8100"], "cwd": str(REPO),
         "optional": False},
    ]
    if cd:
        svc.append({"name": "comfyui", "url": "http://127.0.0.1:8188/system_stats",
                    "timeout": 600, "shell": str(cd / "_run-comfy.bat"), "cwd": str(cd),
                    "optional": True})   # kernel compile can take minutes; never blocks play
        bridge = REPO / "scripts" / "comfyui_openai_bridge.py"
        if bridge.exists():
            svc.append({"name": "bridge", "url": "http://127.0.0.1:8101/health", "timeout": 30,
                        "cmd": [py, str(bridge), "--comfy"], "cwd": str(REPO), "optional": True,
                        "after": "comfyui"})
    svc.append({"name": "backend", "url": "http://127.0.0.1:7000/api/version", "timeout": 90,
                "cmd": [py, "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7000"],
                "cwd": str(REPO), "optional": False, "after": "chroma"})
    return svc


def spawn(svc, job):
    env = dict(os.environ)
    if svc["name"] == "comfyui":
        env["TORCH_BACKENDS_CUDNN_ENABLED"] = "0"    # ZLUDA can't find a cuDNN conv engine
    kw = dict(cwd=svc["cwd"], env=env, stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL, creationflags=CREATE_NO_WINDOW)
    if "shell" in svc:
        p = subprocess.Popen(["cmd.exe", "/c", svc["shell"]], **kw)
    else:
        p = subprocess.Popen(svc["cmd"], **kw)
    assign_to_job(job, p.pid)   # its life is now bound to ours
    return p


# ── Orchestration ────────────────────────────────────────────────────────
def bring_up(job, on_progress=None):
    started = []
    svc = services()
    for i, s in enumerate(svc):
        if http_ok(s["url"], 2):
            log("%s already up — adopting" % s["name"])
            if on_progress:
                on_progress(s["name"], "ready", i, len(svc))
            continue
        log("starting %s…" % s["name"])
        if on_progress:
            on_progress(s["name"], "starting", i, len(svc))
        spawn(s, job)
        started.append(s["name"])
        deadline = time.time() + s["timeout"]
        ok = False
        while time.time() < deadline:
            if http_ok(s["url"], 3):
                ok = True
                break
            time.sleep(2)
        if ok:
            log("%s ready" % s["name"])
            if on_progress:
                on_progress(s["name"], "ready", i, len(svc))
        elif s["optional"]:
            log("%s slow — leaving it to warm up in the background" % s["name"])
            if on_progress:
                on_progress(s["name"], "warming", i, len(svc))
        else:
            log("!! %s did not come up in %ss (required)" % (s["name"], s["timeout"]))
            if on_progress:
                on_progress(s["name"], "failed", i, len(svc))
            return started, False
    return started, True


def save_state(started):
    STATE.write_text(json.dumps({"pid": os.getpid(), "started": started}), encoding="utf-8")


def load_state():
    try:
        return json.loads(STATE.read_text(encoding="utf-8"))
    except Exception:
        return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-pid", type=int, default=0)
    ap.add_argument("--up-only", action="store_true")
    ap.add_argument("--down", action="store_true")
    ap.add_argument("--status", action="store_true")
    args = ap.parse_args()

    if args.status:
        for s in services():
            print("%-9s %s  %s" % (s["name"], "UP  " if http_ok(s["url"], 2) else "down",
                                   s["url"]))
        return 0

    if args.down:
        st = load_state()
        pid = st.get("pid")
        if pid and pid_alive(pid):
            ctypes.windll.kernel32.TerminateProcess(
                ctypes.windll.kernel32.OpenProcess(0x0001, False, pid), 0)
            log("supervisor %s terminated (its job dies with it)" % pid)
        else:
            log("no live supervisor recorded")
        return 0

    # The job MUST be held by this process for its whole life — closing it is
    # what kills the services. Keep the handle in a module-level name.
    global _JOB
    _JOB = make_kill_job()
    started, ok = bring_up(_JOB)
    save_state(started)
    if not ok:
        log("a required service failed — holding the rest up for diagnosis")

    if args.up_only:
        log("up-only: services started, supervisor exiting (job would close!) — "
            "this mode is for testing readiness, not for owning lifetime")
        # In up-only we intentionally DON'T hold the job, so services detach.
        # Re-assign nothing; just report.
        return 0 if ok else 1

    if not args.game_pid:
        log("no --game-pid: watching for the game to appear, else idling")
    log("supervising — services will die when the game (pid %s) exits" % (args.game_pid or "?"))
    # Watch loop: when the game exits, we exit, the job closes, services die.
    grace_start = time.time()
    while True:
        time.sleep(2)
        if args.game_pid:
            if not pid_alive(args.game_pid):
                log("game exited — tearing down the stack")
                break
        else:
            # No PID given: exit if the game never showed up within 2 min.
            if time.time() - grace_start > 120:
                log("no game to watch after 2 min — exiting")
                break
    # Returning closes _JOB (GC) → KILL_ON_JOB_CLOSE fires → services die.
    return 0


if __name__ == "__main__":
    if sys.platform != "win32":
        print("supervisor is Windows-only (Job Objects)."); sys.exit(2)
    sys.exit(main())
