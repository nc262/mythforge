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
→ a registered image `ModelEndpoint` → our **bridge** (`scripts/comfyui_openai_bridge.py`,
`:8101`) → **ComfyUI-ZLUDA** (`:8188`, sibling repo `..\ComfyUI-Zluda`) running SDXL
on the AMD RX 7900 GRE through ZLUDA. Personas are `user_templates` in `presets.json`
sharing one canon ("World Bible"); continuity is the memory system. See
[docs/architecture-review.md](docs/architecture-review.md).

## Hard rules / gotchas (don't relearn these)
- **ComfyUI MUST launch via `zluda.exe`.** `scripts/start-image-stack.ps1` →
  `..\ComfyUI-Zluda\_run-comfy.bat` does this. Launching plain `python main.py`
  (e.g. **ComfyUI Manager's "Restart" button**) fails with
  `cublas64_11.dll … WinError 126` — the ZLUDA stub can't resolve HIP deps without
  the wrapper.
- **ComfyUI auto-update is disabled on purpose.** `_run-comfy.bat` is pinned and does
  NOT `git pull`. The stock `comfyui-n.bat` pulls upstream on every launch, which has
  pulled an incompatible commit (`simple_vram_headroom` crash). To update ComfyUI:
  `git pull` manually, then test.
- **ZLUDA trips Windows Defender** (false positive on its DLLs/`nccl.dll`). A Defender
  exclusion for `..\ComfyUI-Zluda` is required or the install silently breaks. See
  `scripts/fix-zluda-elevated.ps1`.
- **cuDNN must be OFF for SDXL on ZLUDA** or conv2d throws
  `CUDNN_STATUS_EXECUTION_FAILED`. The bridge bakes a `CUDNNToggleAutoPassthrough`
  node (enable_cudnn=False) into every workflow.
- **`presets.json` is cached in memory at startup** (`PresetManager.__init__`).
  Editing the file directly does nothing until Odysseus restarts, and a UI preset-save
  will overwrite your file edit with the stale cache. Edit via the API/UI, or edit the
  file then **restart Odysseus**.
- **The companion model `gurubot/girl:latest` will not call tools.** It stays in
  character but never emits a tool call, so personas don't auto-generate images in
  chat. Image generation is driven explicitly (the bridge `character` param), not by
  the model deciding to. A tool-capable model (e.g. `qwen2.5:14b`) calls tools but
  breaks the persona voice — a known tradeoff.
- **The affiliate-tag-style invariant here:** the real diffusion happens only in
  ComfyUI; Odysseus never loads torch/CUDA itself. Its venv is CPU-only torch and that
  is correct — don't "fix" it.
- ComfyUI's venv must be **Python 3.11** (ZLUDA's triton/torch patches are cp311-only;
  machine default `python` is 3.13).

## Workflow before changing anything
DISCOVER → PLAN → CHALLENGE → EXECUTE → VERIFY → REVIEW → IMPROVE. Weigh architecture,
security, operational, and cost impact (the four review docs below).

## Verifying changes
- App: restart `uvicorn`, hit `http://localhost:7000`. Presets only reload on restart.
- Image stack: `pwsh scripts/start-image-stack.ps1`; `curl :8101/health` and
  `:8101/v1/models`; ComfyUI UI at `:8188`.
- Personas / image trigger: `python scripts/test_persona_image.py <model> [persona|plain]`
  drives the real agent loop and reports whether `generate_image` fired.
- See [docs/testing-strategy.md](docs/testing-strategy.md).

## Local services & ports
| Port | Service |
|---|---|
| `7000` | Odysseus app (uvicorn) |
| `8188` | ComfyUI-ZLUDA (image engine) |
| `8101` | OpenAI→ComfyUI bridge |
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
