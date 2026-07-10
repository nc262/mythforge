# Testing Strategy — Odysseus (local deployment)

What to check before trusting a change. Verification over assumptions: confirm with
output, don't infer.

## 1. App
- Restart `uvicorn` (presets/config only reload on restart) and load
  `http://localhost:7000`.
- Upstream Python tests live in `tests/` — run `pytest` for core regressions when
  touching `src/`/`routes/`/`core/`.
- **Preset changes:** editing `data/presets.json` does nothing live (cached at startup).
  Verify by restarting and checking the **Prompt → Persona** dropdown, or push via
  `POST /api/presets/templates` (admin).

## 2. Image stack (bring-up)
```powershell
pwsh scripts/start-image-stack.ps1
```
Then confirm each layer:
- ComfyUI: `http://127.0.0.1:8188/system_stats` → should report
  `AMD Radeon RX 7900 GRE [ZLUDA]`.
- Bridge: `curl http://127.0.0.1:8101/health` → `status: ok`;
  `curl http://127.0.0.1:8101/v1/models` → lists the checkpoint (proves bridge↔ComfyUI).

## 3. Image generation (end to end)
- **Direct bridge (plain):**
  ```bash
  curl -s -X POST http://127.0.0.1:8101/v1/images/generations \
    -H "Content-Type: application/json" \
    -d '{"prompt":"a cozy cabin at dusk, photorealistic","quality":"low"}' -o out.json
  ```
  Decode `data[0].b64_json` → expect a valid PNG. First run is slow (kernel compile),
  then ~7 s.
- **Character-conditioned:** add `"character":"meg"` (needs photos in
  `..\ComfyUI-Zluda\input\characters\meg`). First IP-Adapter run compiles (~160 s),
  then fast. Inspect the saved `..\ComfyUI-Zluda\output\odysseus_*.png` for likeness.
- **Through Odysseus:** `python scripts/wire_image_provider.py` (once), then
  `do_generate_image(...)` should return an `image_url` and save to the gallery.

## 4. Personas (conversation + tool behavior)
- `python scripts/test_persona_image.py <model> [persona|plain]` drives the **real
  agent loop** and reports whether `generate_image` actually fired. Known results:
  `gurubot/girl:latest` → stays in character, never calls the tool; `qwen2.5:14b` →
  calls tools but inconsistently and breaks the persona voice.
- Persona/canon check: open chats with Megan and Lilly and confirm they reference the
  shared canon (each other, Mochi, the family) and never contradict it. Watch for the
  old **Brain → identity** memory entries resurfacing and conflicting with the World
  Bible (reconcile if so).
- Run the harness with `PYTHONIOENCODING=utf-8` (personas emit emoji; cp1252 console
  will crash on print otherwise).

## 5. Gotcha checks before declaring success
- ComfyUI launched via **`zluda.exe`** (not Manager restart) — else `cublas64_11.dll`
  WinError 126.
- `comfy/zluda.py` patch applied (the launch wrapper copies it each start).
- Defender exclusion still present for `..\ComfyUI-Zluda` (else next ZLUDA fetch is
  quarantined).
- cuDNN off in any custom workflow (or conv2d fails on ZLUDA).
- The image `ModelEndpoint` points at the **local** bridge, not an OpenAI image model
  (avoids surprise cloud billing).
