# Code Style — Odysseus (local deployment)

Match the surrounding code. This captures the conventions already in the repo plus the
ones for the local automation scripts added here.

## Python (app: `core/`, `src/`, `routes/`, `services/`)
- **Module docstrings** at the top of every file saying what it is and (often) why it
  was split out. Keep them.
- **Type hints** on function signatures; `Optional[...]`, `Dict`, `List`, `Tuple`.
- `snake_case` functions/vars, `PascalCase` classes. Private helpers prefixed `_`.
- **Logging, not prints:** `logger = logging.getLogger(__name__)`; warn/info/debug
  appropriately. Background/MCP failures are caught and logged, not raised into the
  request path.
- **FastAPI:** routers built in `routes/*.py` via a `setup_*_routes(...)` factory;
  admin-gated endpoints use `Depends(require_admin)`. Pydantic models for request bodies.
- **DB:** SQLAlchemy models in `core/database.py`; access via `SessionLocal()` and
  always `db.close()` (try/finally). Schema changes ship with a `_migrate_*` helper.
- **Settings:** read/write through `src/settings.py` (`load_settings`/`save_settings`,
  `get_setting`); don't hand-parse `settings.json`. Atomic file writes via
  `core/atomic_io.py`.
- **Comments** explain *why* (especially non-obvious workarounds) — the codebase has a
  strong "here's the trap we hit" comment culture; preserve it when adding workarounds.
- Tests in `tests/` (pytest), one concern per file, descriptive names.

## Frontend (`static/`)
- Vanilla modular JS under `static/js/` (`chat.js`, `presets.js`, `memory.js`, …); no
  build step. Keep new UI logic in the matching module.
- Single `index.html` with modal/panel sections; CSS in `style.css` using CSS variables
  (`var(--bg)`, etc.) — never hardcode theme colors.

## Local automation scripts (`scripts/`)
- **The bridge (`comfyui_openai_bridge.py`)** mirrors `diffusion_server.py`'s posture:
  standalone FastAPI + `argparse`, async `httpx`, loopback-only `TrustedHostMiddleware`,
  OpenAI-shaped request/response, all generation params behind CLI flags with sane
  defaults. New behavior goes behind a flag with a default that preserves current
  behavior.
- **PowerShell scripts** (`start-image-stack.ps1`, `setup-hip-env.ps1`,
  `fix-zluda-elevated.ps1`): start with a header comment (what it does, when to run,
  how to undo). Idempotent (check before acting — e.g. test the port before launching).
  Use **absolute paths**; don't rely on the caller's cwd. Privileged scripts state that
  they need admin and what exactly they change.
- **Launching `.bat`/external processes from automation:** use a wrapper `.bat` that
  `cd /d`s to the target and calls by **full path**, launched detached via
  `Start-Process` so it survives the shell. Avoid single-quoted PowerShell strings with
  embedded quotes passed to `cmd` (they get mangled). Long-lived servers are launched
  detached, never as a foreground tool call that would block.
- Keep one-off scratch files out of the tree; the keepers are the bridge, the launcher,
  the wiring/setup scripts, and the persona smoke test (`test_persona_image.py`).

## Naming & data
- Generated images: `odysseus_*.png` prefix (ComfyUI `SaveImage`) → surfaced in the
  gallery and `data/generated_images/`.
- Character reference photos: `..\ComfyUI-Zluda\input\characters/<name>/` (lowercase
  name; the bridge sanitizes it).
- Don't hardcode model names where a setting exists (`image_model`, `default_model`,
  etc.); resolve through settings/`_resolve_model`.
