# Architecture Review — Odysseus (local deployment)

Scope: the system as it runs on this machine, with emphasis on the local
image-generation stack and companion personas added on top of upstream.

## 1. Base application
- **Entry:** `app.py` → FastAPI, served by `uvicorn app:app --host 0.0.0.0 --port 7000`
  (launched by `start-odysseus.ps1`). Single-page UI from `static/` (`index.html` +
  `app.js` + `js/` modules).
- **Core (`core/`):** `auth.py` (sessions, admin gating), `database.py` (SQLAlchemy
  models incl. `ModelEndpoint`, `GalleryImage`), `middleware.py`, `constants.py`.
- **Logic (`src/`):** `agent_loop.py` (streaming agent w/ tool calls), `ai_interaction.py`
  (model resolution `_resolve_model`, `do_generate_image`), `chat_processor.py`
  (context preface: preset prompt + memory + RAG), `preset_manager.py`,
  `settings.py`, `tool_*` (schemas/parsing/execution/index), `builtin_mcp.py`.
- **Routes (`routes/`):** chat, session, preset, memory, model, gallery, etc.
- **Services (`services/`):** memory, docs, search, `hwfit` (Cookbook).
- **Data (`data/`, gitignored):** `app.db` (sessions/messages/docs/gallery),
  `presets.json`, `memory.json`, `chroma/`, `uploads/`, `auth.json`, `settings.json`.

## 2. Model/LLM flow
Endpoints live in the `model_endpoints` table (admin-managed; auto-discovered via
`/v1/models`). Locally the LLM endpoint is **Ollama** at `http://localhost:11434/v1`
(GPU-accelerated via ROCm; `gurubot/girl:latest`, `qwen2.5:14b`, etc.). The agent loop
chooses **native function-calling** vs **text-tag tool parsing** per
`ModelEndpoint.supports_tools` + model-name heuristics (`agent_loop.py`). `generate_image`
is a catalog/tag tool, **not** in `FUNCTION_TOOL_SCHEMAS`.

## 3. Local image-generation stack (added)
OpenAI-API-shaped end to end, so Odysseus needs no core changes:

```
Odysseus do_generate_image / generate_image tool
   │  POST /v1/images/generations   (resolves image ModelEndpoint)
   ▼
Bridge  scripts/comfyui_openai_bridge.py   :8101   (OpenAI-compatible shim)
   │  builds a ComfyUI workflow, POST /prompt, polls /history, fetches /view
   ▼
ComfyUI-ZLUDA   ..\ComfyUI-Zluda   :8188   (SDXL on AMD via ZLUDA)
```

- **Engine:** ComfyUI-Zluda (patientx fork) on the **AMD RX 7900 GRE (gfx1100, 16 GB)**
  via HIP SDK 6.4.2 + ZLUDA 3.9.5. Checkpoint: **DreamShaper XL Turbo** (~6 steps).
- **Bridge:** exposes `/v1/models`, `/v1/images/generations`, `/health`. Maps
  OpenAI quality→steps, builds the SDXL graph, **forces cuDNN off** (ZLUDA conv2d
  bug). Loopback-only (TrustedHost).
- **Character conditioning (IP-Adapter):** when the request includes a `character`
  (e.g. `meg`), the bridge picks the best reference photo from
  `..\ComfyUI-Zluda\input\characters/<name>/` and builds an **IPAdapterUnifiedLoader
  (PLUS) + IPAdapterAdvanced** workflow so the character's look stays consistent across
  scenes. Models: `models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors` +
  `models/clip_vision/CLIP-ViT-H-14...safetensors`.
- **Registration:** `scripts/wire_image_provider.py` inserts an image-type
  `ModelEndpoint` (`http://localhost:8101/v1`) and sets `image_model`. Generated images
  are saved to the gallery (`GalleryImage`) and `data/generated_images/`.

## 4. Personas & continuity
- Lilly & Megan are `user_templates` in `presets.json`, each = **shared "World Bible"
  canon** (identical block: husband/father = user, Megan = wife, Lilly = grown
  daughter, Mochi = cat; romance scoped to the married couple) **+ a per-character
  sheet** (voice, traits, how they see each other). A `group_presets` entry
  ("Megan & Lilly") runs both round-robin on `gurubot/girl:latest`.
- **Canon** lives in the prompt (always present, reliable). **Evolving story** lives in
  the memory system (`memory.json` + ChromaDB; auto-extracted, recalled when relevant).
- The `Brain` UI = the memory system; "identity" is a memory *category* (separate from
  the persona prompts).

## 5. Deploy / runtime
- One Windows PC. Odysseus (uvicorn), Ollama, ComfyUI-ZLUDA, and the bridge are
  separate long-lived processes. Image services are started by
  `scripts/start-image-stack.ps1` (ComfyUI launched **detached** so it survives;
  bridge hidden). Not auto-started at logon (a Startup launcher was deliberately not
  installed — see devsecops).

## 6. Scaling limits / constraints
- **VRAM is the ceiling (16 GB).** LLM (~5.5 GB) + SDXL (~5 GB) coexist; a 32B LLM
  (`deepseek-r1:32b`, ~20 GB) will spill to CPU and crawl. `qwen2.5:14b` is the
  sweet spot for a 16 GB card.
- **ZLUDA first-run compiles kernels** per new op-shape (one-time minutes, then cached
  in `%LOCALAPPDATA%\ZLUDA\ComputeCache`). New resolutions/models recompile.
- **Single host, single user** assumed. `presets.json` cache means horizontal scaling
  would need a shared store + reload signal.
- Image generation is serial through one ComfyUI; concurrent requests queue.
