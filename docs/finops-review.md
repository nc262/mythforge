# FinOps Review — Odysseus (local deployment)

The defining fact: **this stack is entirely self-hosted — there is no recurring cloud
spend.** Cost is hardware + electricity + your time. This doc frames "cost of change"
in those terms.

## 1. Standing costs
- **Hardware (sunk):** one Windows PC — Ryzen 5 7600, 32 GB RAM, AMD RX 7900 GRE (16 GB).
- **Electricity:** the only ongoing cash cost. The GPU draws meaningfully only during
  generation/inference; idle ComfyUI + Ollama mostly hold VRAM and sip power. Leaving
  all services running 24/7 costs more than starting them on demand.
- **No per-token / per-image API fees:** LLMs (Ollama) and images (ComfyUI) run locally.

## 2. Resource budget (the real constraint)
- **VRAM 16 GB** is the scarce resource, not dollars:
  - LLM ~5.5 GB (`gurubot/girl`) or ~9 GB (`qwen2.5:14b`) + SDXL ~5 GB → coexist fine.
  - `deepseek-r1:32b` (~20 GB) does **not** fit → CPU spill → very slow (a "cost" in
    latency, not money). Avoid for interactive use.
- **Disk:** models are the bulk — DreamShaper XL Turbo ~6.5 GB, IP-Adapter ~0.8 GB,
  CLIP-vision ~2.4 GB, plus Ollama models (several GB each). Budget ~30–50 GB. 391 GB
  free at setup.
- **Time:** first ZLUDA generation for a new op-shape compiles kernels (~minutes,
  one-time, cached). Steady-state image gen ≈ **7 s** at 1024×1024 turbo.

## 3. Cost of common changes
- **Add a model (LLM or checkpoint):** disk + download time only. Check it fits VRAM
  alongside whatever else is loaded.
- **Add IP-Adapter FaceID / a LoRA / ControlNet:** more disk + VRAM + first-run
  compile; verify it still fits the 16 GB budget.
- **Higher quality/steps or bigger resolutions:** longer generation + a one-time
  recompile per new resolution. Linear-ish in steps.
- **Run everything 24/7 / autostart:** higher idle power draw; weigh against the
  convenience of not running `start-image-stack.ps1`.

## 4. The one place cloud cost could sneak in
- `do_generate_image` can target **OpenAI `gpt-image-1`** instead of the local bridge
  (it auto-detects gpt-image/DALL·E models). That path bills per image. This deployment
  deliberately uses the **local** bridge (`image_model` = the local checkpoint), so keep
  it that way unless you intentionally want paid cloud images. Same for any
  OpenAI/OpenRouter LLM endpoints — adding them introduces metered spend.

## 5. Recommendation
Keep it local-first. Start the image stack on demand rather than at logon if power/idle
VRAM matters. Treat VRAM (not money) as the budget you optimize against.
