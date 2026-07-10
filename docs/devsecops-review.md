# DevSecOps Review — Odysseus (local deployment)

Odysseus is an admin console with powerful local tools (shell, file I/O, model
downloads, web, email/calendar). Treat it accordingly. This doc covers *this*
deployment's posture and the security-relevant choices made adding the image stack.

## 1. Authentication & exposure
- `AUTH_ENABLED=true` (keep it). Admin-only routes: model/endpoint management, MCP,
  tokens, webhooks, settings, backup. Non-admin users get no shell/python/file access
  by default.
- ⚠️ **The app is bound to `0.0.0.0:7000`** (reachable on the LAN, not just loopback).
  Acceptable only if intentional (e.g. phone access over a trusted LAN/Tailscale).
  Recommendations: keep `AUTH_ENABLED=true` and `LOCALHOST_BYPASS=false`; prefer
  binding `127.0.0.1` and fronting with a trusted reverse proxy / Tailscale; do **not**
  expose `:7000` to the public internet without HTTPS + a proxy.
- Bundled/local service ports (`8188` ComfyUI, `8101` bridge, `11434` Ollama, ChromaDB,
  SearXNG, ntfy) must stay **internal-only** — never expose them directly.

## 2. The bridge (`:8101`)
- Server-to-server only: `TrustedHostMiddleware` allows loopback hosts; no CORS by
  default. It takes a `prompt` + optional `character`/`size`/`quality` and drives
  ComfyUI. No auth (loopback trust) — keep it bound to localhost.
- Input note: `character` is sanitized (alnum/`-`/`_`, lowercased) before building a
  filesystem path, so it can't traverse out of `input/characters/`.

## 3. AMD/ZLUDA security tradeoffs (explicit, user-approved)
- **Windows Defender exclusion** for `..\ComfyUI-Zluda` was added (ZLUDA's DLLs are a
  known AV false-positive that otherwise quarantines `nccl.dll` and breaks the install).
  This is a real reduction in AV coverage scoped to one folder. Reversible:
  `Remove-MpPreference -ExclusionPath "<path>"`. Only ZLUDA-related binaries live there;
  don't drop untrusted files into that folder.
- **Third-party ComfyUI node** (`ComfyUI_IPAdapter_plus`, cubiq) was installed via
  ComfyUI Manager. ComfyUI auto-runs everything in `custom_nodes/` at startup — treat
  node installs as running third-party code. Install only from trusted authors via the
  Manager; review before adding more.

## 4. Supply chain
- Model weights pulled from Hugging Face (`h94/IP-Adapter`, `Lykon/...`,
  Stability/AMD). Large binaries — verify sizes after download. ZLUDA binary comes from
  `lshqqytiger/ZLUDA` releases.
- ComfyUI is **pinned** (auto-update disabled) precisely because an unattended
  `git pull` pulled a breaking upstream commit. Update deliberately and test.

## 5. Secrets & data
- Keep `.env`, `data/` (db, `auth.json`, `settings.json`, memory, uploads, generated
  media, gallery), and any API tokens out of Git and shared shares (gitignored by
  default). Review `data/auth.json` after first boot: disable open signup, keep only
  your account admin.
- Persona reference photos in `..\ComfyUI-Zluda\input\characters/` and generated media
  in `data/generated_images/` are personal — keep them local.
- Rotate any key/token ever pasted into a chat, screenshot, or log.

## 6. Operational safety
- **Image stack is not auto-started at logon by design** — a logon-startup launcher is
  an unrequested persistence mechanism and was intentionally not installed. Start the
  stack manually with `scripts/start-image-stack.ps1`. If you *want* autostart, add the
  Startup-folder launcher yourself (documented in chat history) so it's a conscious
  choice.
- `scripts/setup-hip-env.ps1` and `fix-zluda-elevated.ps1` require admin (System env
  vars / Defender). Read them before running; they only touch HIP env + the one
  exclusion.
- Before publishing/forking: `git status --short` and confirm no `data/`, `.env`,
  uploads, reference photos, or local DBs are staged.
