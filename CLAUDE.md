# CLAUDE.md — Odysseus (local fork)

Project context for AI-assisted work on this machine's Odysseus install. Read this
first, then the relevant file in `docs/`.

## What this is
A self-hosted AI workspace (chat, agents, memory, documents, email, calendar, deep
research) — upstream project `pewdiepie-archdaemon/odysseus`, branch `dev`. This
machine runs it natively on **Windows** and has been extended with a **local,
The upstream `README.md` documents the base app; the `docs/` set below documents
*this* deployment and the local additions.

## Architecture in one paragraph
`uvicorn app:app` serves the FastAPI app on `:7000` (currently bound `0.0.0.0`).
It renders a single-page UI from `static/` and persists everything to `data/`
(`app.db`, `presets.json`, `memory.json`, `chroma/`, uploads, `auth.json`,
`settings.json`). Chat/agent calls go to model endpoints in the `model_endpoints`
table (`core/database.py`); locally that's **Ollama** (`localhost:11434`, GPU via
ROCm). Image generation is OpenAI-API-shaped: `src/ai_interaction.do_generate_image`
→ a registered image `ModelEndpoint` → **stable-diffusion.cpp** (`:8189`) running
SDXL on the AMD RX 7900 GRE through **Vulkan**. No CUDA, no ZLUDA, no Python. Personas are `user_templates` in `presets.json`
sharing one canon ("World Bible"); continuity is the memory system. See
[docs/architecture-review.md](docs/architecture-review.md).

## Hard rules / gotchas (don't relearn these)
- **The image engine is `stable-diffusion.cpp` on Vulkan** (`scripts/start-image-sdcpp.ps1`,
  `:8189`). One native binary, one `.safetensors` checkpoint, no Python. It serves
  the OpenAI image API directly, so `scripts/comfyui_openai_bridge.py` is no
  longer in the path either.
- **ComfyUI and ZLUDA are no longer part of this stack.** ComfyUI is left
  installed for other projects; it is simply not started, and nothing here talks
  to it. Everything below used to be required and is now dead — kept only so the
  next person understands why the tower existed and why it is gone:
  - ~~ComfyUI MUST launch via `zluda.exe` or `cublas64_11.dll … WinError 126`~~
  - ~~A Windows Defender exclusion for `..\ComfyUI-Zluda`, or the install silently breaks~~
  - ~~cuDNN must be OFF for SDXL on ZLUDA or conv2d throws `CUDNN_STATUS_EXECUTION_FAILED`~~
  - ~~ComfyUI's venv must be Python 3.11 (ZLUDA's patches are cp311-only)~~
  - ~~ComfyUI auto-update disabled on purpose (upstream pulled an incompatible commit)~~

  Every one of those existed for a single reason: **ComfyUI wants CUDA and this
  is an AMD card.** ZLUDA is a CUDA shim, and all of that was scaffolding around
  the mismatch. A Vulkan backend needs no CUDA, so the scaffolding had nothing
  left to hold up. Measured after the swap: a GM turn went **19.3s → 3.7s**
  steady state (~5.2x), because idle sd-server holds **118 MB** of VRAM where
  ComfyUI held ~7.4 GB — it loads per request instead of staying resident
  (godot/docs/Architecture-InProcess.md).
- **`--vae-tiling` is load-bearing, not tuning.** Without it the VAE decode asks
  for a Vulkan buffer past this device's limit, falls back to a slow path, and
  eats 36.2s of a 50.4s image. Tiled: 3.1s decode, 19.9s image, pixel-identical
  at the same seed. Set it in all three launch paths (`ecosystem.config.js`,
  `scripts/start-image-sdcpp.ps1`, `scripts/mythforge_supervisor.py`). Also:
  sd-server **ignores the `steps` field in the request body** — steps are a
  launch flag or nothing.
- **If ComfyUI comes back, something is supervising it.** Two things did: the
  pm2 app `image-stack` (a port-poller that relaunched it; `pm2 save` is needed
  or `dump.pm2` restores it) and a logon script `odysseus-image-stack.vbs`
  pointing at the *older* `Code/odysseus` checkout — outside this repo entirely.
  Both are disabled; check pm2's dump and the Startup folder before believing a
  kill worked.
- **The invariant that still holds:** the app never loads torch/CUDA itself —
  diffusion happens entirely in the image engine. Its venv is CPU-only torch and
  that is correct; don't "fix" it. The engine changed underneath (sd.cpp instead
  of ComfyUI); the separation did not.

## Workflow before changing anything
DISCOVER → PLAN → CHALLENGE → EXECUTE → VERIFY → REVIEW → IMPROVE. Weigh architecture,
security, operational, and cost impact (the four review docs below).

## Verifying changes
- App: restart `uvicorn`, hit `http://localhost:7000`. Presets only reload on restart.
- Image stack: `pwsh scripts/start-image-sdcpp.ps1`; `curl :8189/v1/models`;
  a browser WebUI is served at `:8189` for eyeballing prompts.
- Personas / image trigger: `python scripts/test_persona_image.py <model> [persona|plain]`
  drives the real agent loop and reports whether `generate_image` fired.
- See [docs/testing-strategy.md](docs/testing-strategy.md).

## Local services & ports
| Port | Service |
|---|---|
| `7000` | Odysseus app (uvicorn) |
| `8189` | stable-diffusion.cpp (image engine, Vulkan) |
| ~~`8188`~~ | ~~ComfyUI-ZLUDA~~ — no longer part of this stack |
| ~~`8101`~~ | ~~OpenAI→ComfyUI bridge~~ — sd.cpp speaks the API itself |
| `11434` | Ollama (LLMs) |
| `8100`/`8080`/`8091` | ChromaDB / SearXNG / ntfy (if used) |

## The `docs/` set
| Doc | Covers |
|-----|--------|
| [architecture-review.md](docs/architecture-review.md) | System design, data flow, the local image/persona stack, scaling limits |
| [devsecops-review.md](docs/devsecops-review.md) | Auth, network exposure, AV exclusion, third-party nodes, supply chain |
| [finops-review.md](docs/finops-review.md) | What this costs to run (all local); VRAM budget; per-image cost |
| [testing-strategy.md](docs/testing-strategy.md) | Verify gates for the app, image stack, and personas |
| [troubleshooting.md](docs/troubleshooting.md) | RCAs for the ZLUDA / ComfyUI / preset issues hit during setup |
| [code-style.md](docs/code-style.md) | Conventions for the codebase and the local automation scripts |
