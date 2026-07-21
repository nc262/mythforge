# App Lifecycle — one exe, one lifetime

**Directive (2026-07-21):** Mythforge should start and stop like a real app —
click the exe and ComfyUI, Ollama, Chroma and the backend all boot; close the
window and they all die. No "start the server first", no orphaned Python.

## The mechanism

A **service supervisor** (`scripts/mythforge_supervisor.py`) owns a Windows
**Job Object** created with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. Every service
it starts is assigned to that job. When the supervisor's handle to the job is
released — it exits, crashes, or is killed — Windows terminates the whole job.
The death-with-parent guarantee is the OS's, not ours. *(Proven: closing the
job handle kills an assigned child every time.)*

```
Mythforge.exe  ──spawns──▶  supervisor  ──owns──▶  [Job Object: KILL_ON_CLOSE]
     │                          │                     ├── ollama serve
     │                          │ watches game PID    ├── chroma
     │                          │                     ├── ComfyUI (ZLUDA)
     └── exits ────────────────▶ detects, releases ──▶├── image bridge
                                  job → all die        └── uvicorn backend
```

Two independent teardown paths, so nothing is ever orphaned:
1. **Clean:** the supervisor watches the game's PID (`WaitForSingleObject`, not
   a pipe — survives a game crash). Game gone → supervisor exits → job closes.
2. **Backstop:** if the supervisor itself dies unexpectedly, its job handle
   closes anyway → services die anyway.

## Idempotent and safe over a dev stack

- A service already answering its health URL is **adopted**, not restarted.
- Only services the supervisor **started** are in its job; adopted ones are
  left alone on shutdown. *(Proven: over a running stack, a cold `chroma` was
  started and later killed with the job, while the adopted backend survived.)*
- So running the exe while you have a hand-started stack up disturbs nothing.

## Start order and readiness

Dependency-ordered, health-checked (`ollama → chroma → comfyui → bridge →
backend`). Services marked **optional** (ComfyUI, bridge) never block the game:
ComfyUI's first-launch ZLUDA kernel compile can take minutes, and art warms up
behind play. The game releases to the menu the moment the **backend** (:7000)
answers — the one service it strictly needs.

`comfyui` is started with `TORCH_BACKENDS_CUDNN_ENABLED=0` (ZLUDA can't reliably
find a cuDNN convolution engine — see the ComfyUI note in WorldCompiler.md).

## The Godot side

`autoload/services.gd` (`Services`):
- On `_ready`, **only in a shipped build** (`OS.has_feature("standalone")` and
  not headless), spawns the supervisor detached with `--game-pid <own pid>`.
  In the editor and in harness runs it does nothing — those manage services by
  hand.
- `await_backend()` polls `/api/version`, emitting world-flavoured progress
  ("Waking the realm…", "Lighting the forges…") so the login screen shows a
  real, honest boot instead of failing fast. The cold-boot minute reads as work.

## Standalone control

```
python scripts/mythforge_supervisor.py --status       # what's up
python scripts/mythforge_supervisor.py --up-only      # start + verify, detach
python scripts/mythforge_supervisor.py --game-pid N   # start + watch PID N
python scripts/mythforge_supervisor.py --down         # stop a running supervisor
```

## Known limit — packaging

The supervisor resolves the repo relative to the exe (with a dev-checkout
fallback), so on this box `Desktop\Mythforge.exe` finds `Code/mythforge` and its
`venv`. A **distributed** build would need the Python backend + venv shipped
alongside the exe (and Ollama/ComfyUI installed by `install.ps1`); bundling the
Python stack into the download is a separate packaging task. The lifecycle
mechanism itself is complete and does not change.
