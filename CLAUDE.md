# CLAUDE.md — Mythforge

Project context for AI-assisted work on this machine. Read this first, then the
relevant file in `docs/` or `godot/docs/`.

## What this is
A single-player desktop RPG: a Godot 4.7 game whose Game Master is a local LLM.
It began as a fork of the `odysseus` AI workspace (chat, agents, documents,
email, calendar, deep research) and **that workspace is gone** — the browser UI,
the FastAPI backend, and the ~79k lines behind them.

## Architecture in one paragraph
**The game is the whole application.** `Mythforge.exe` runs llama.cpp in its own
process through the **NobodyWho** GDExtension (Vulkan on the AMD RX 7900 GRE):
the narrator, campaign memory (embeddings + cosine recall), the cast codex, the
quest log, the world tick, the Worldsmith, the World Compiler and
speech-to-text. Saves are JSON files under `user://`. The one other process is
**stable-diffusion.cpp** on `:8189`, which serves the OpenAI image API itself, so
the game POSTs to it directly. There is no server, no login, no session, no
database and no Ollama. See
[godot/docs/Architecture-InProcess.md](godot/docs/Architecture-InProcess.md) and
[godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md).

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
- **The invariant that still holds:** nothing outside the image engine loads
  torch/CUDA. The engine changed underneath (sd.cpp instead of ComfyUI) and the
  app that used to sit in front of it is gone; the separation did not.
- **A grammar and a sampler chain REPLACE each other** in NobodyWho, so a
  schema-constrained call runs with no top-k/top-p/temperature/penalties. Never
  let one call both invent and serialise — think in prose, then serialise. This
  cost three wrong diagnoses before it was measured; see
  [godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md).

## Workflow before changing anything
DISCOVER → PLAN → CHALLENGE → EXECUTE → VERIFY → REVIEW → IMPROVE. Weigh architecture,
security, operational, and cost impact (the four review docs below).

## Verifying changes
Four harnesses, all headless, all offline (`Api.test_mode`), run from the repo root:

```
<godot> --headless --path godot res://tests/self_check.tscn      # rules, prompts, parsers
<godot> --headless --path godot res://tests/click_driver.tscn    # every station reachable
<godot> --headless --path godot res://tests/ui_playthrough.tscn  # a real game, scripted
<godot> --headless --path godot res://tests/local_stack.tscn     # REAL models + GPU
<godot> --headless --path godot res://tests/bench_gm.tscn        # turn latency + repetition
```

`local_stack` and `bench_gm` drive the actual model — they are the only ones that
can tell you an answer is *good*, not merely well-shaped. **Re-export after any
`godot/**` change** or you are testing a stale exe.

Image engine: `pwsh scripts/start-image-sdcpp.ps1`; `curl :8189/v1/models`.

## Local services & ports
| Port | Service |
|---|---|
| `8189` | stable-diffusion.cpp (image engine, Vulkan) — **the only service** |
| ~~`7000`~~ | ~~FastAPI backend~~ — deleted; the game has no server |
| ~~`11434`~~ | ~~Ollama~~ — it served the backend's helpers; they are in-process |
| ~~`8188`~~/~~`8101`~~ | ~~ComfyUI-ZLUDA / bridge~~ — sd.cpp speaks the API itself |

## The docs that matter now
| Doc | Covers |
|-----|--------|
| [godot/docs/Architecture-InProcess.md](godot/docs/Architecture-InProcess.md) | What moved into the game, and what the HTTP costume cost |
| [godot/docs/LocalLLM-Tuning.md](godot/docs/LocalLLM-Tuning.md) | **Read before touching a model call.** Sampler/grammar limits, with numbers |
| [godot/docs/WorldForge-UX.md](godot/docs/WorldForge-UX.md) | Why the forge felt cookie-cutter; five of six fixes shipped |
| [docs/troubleshooting.md](docs/troubleshooting.md) | RCAs for the ZLUDA / ComfyUI / preset issues hit during setup |
| [docs/code-style.md](docs/code-style.md) | Conventions for the codebase and the local automation scripts |

The `docs/` reviews (architecture, devsecops, finops, testing-strategy) describe
the **Odysseus workspace**, which no longer exists. They are kept as history of
why the tower was built; do not treat them as current.
