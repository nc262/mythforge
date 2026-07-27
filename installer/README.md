# Mythforge one-click installer

Turns the desktop edition into a normal game app: a friend downloads one
`Mythforge-Setup.exe`, clicks through, and everything — the local AI Game Master,
the ComfyUI art engine, and the game — installs and configures itself on their
machine. Nothing else to download, no terminal, no accounts.

## The pieces

| File | Role |
|------|------|
| `Mythforge-Setup.iss` | Inno Setup script → the one `.exe`. Bundles the lean backend, drops the shortcut, kicks off first-run setup. |
| `bootstrap.ps1` | First-run "download & configure". **Reuses [`scripts/install.ps1`](../scripts/install.ps1)** for the hard parts (GPU detect → Ollama + models, ComfyUI on CUDA/ZLUDA/none, the app venv), then downloads the game client. Idempotent — doubles as a repair. |
| `mythforge.ps1` | The launcher — the only thing a player runs. Self-heals (runs `bootstrap` if unconfigured), starts Ollama → backend → image stack on private loopback ports, seeds the two `model_endpoints` rows, launches the game, and tears it all down on quit. |

Design choice: this is a **thin wrapper over what already worked**. The GPU
matrix, Ollama, ComfyUI, model pulls, and venv are all `scripts/install.ps1`
(unchanged). The new code only adds the game client, the endpoint seeding, and
the runtime orchestration — the parts the desktop edition needs on top.

## Build it

```
iscc /DClientUrl="https://github.com/<you>/mythforge/releases/download/vX/Mythforge.exe" installer\Mythforge-Setup.iss
```

→ `installer\Output\Mythforge-Setup.exe`. Publish that plus `Mythforge.exe`
(the exported Godot client, ~1.6 GB) as release assets. Everything else the
installer fetches from official sources (Ollama, ComfyUI, HuggingFace, the
Ollama model registry), so those are the only two files you host.

### The baked worlds are release assets too, not git

`godot/baked/*.zip` (~1.4 GB, six worlds) is **gitignored on purpose**. The exe
bundles them at export time, and players get them inside `Mythforge.exe`, so a
clone never needs them — keeping them out stops the repo growing by gigabytes
per bake. Rebuild locally with `tests/bake_worlds.tscn` + `scripts/bake_zip.py`
(see [AssetBake.md](../godot/docs/AssetBake.md)), or attach them to the release
if you want them downloadable on their own.

**Consequence to know:** a fresh clone has no `godot/baked/`, so an export from
it produces an exe with **no pre-baked worlds** until you either bake them or
drop the release zips into `godot/baked/`.

## What's verified, and what needs a clean box

Validated on the dev machine (AMD / ZLUDA):

- Both PowerShell scripts parse clean.
- The endpoint-seed POST is idempotent — dedupes on `base_url`, adds no
  duplicate rows against the live backend.
- The backend, Ollama, and ComfyUI health/port checks match the running stack.
- `scripts/install.ps1` is the project's existing, in-use installer.

**Not yet exercised on a clean machine — validate before shipping wide:**

- A full first-run `bootstrap` on a fresh box (it clones ComfyUI as a sibling of
  the install dir and pulls ~10 GB; not run here to avoid disturbing the dev
  stack).
- The **NVIDIA / CUDA** path (this box is AMD only).
- Compiling the `.iss` (needs Inno Setup 6 installed).
- Windows SmartScreen: an unsigned installer shows a warning. Code-sign
  `Mythforge-Setup.exe` for a clean download experience, or document the
  "More info → Run anyway" click.

The **AMD-on-Windows (ZLUDA)** path carries the known gotchas from the root
`CLAUDE.md` — Defender exclusion, cuDNN off, the HIP SDK step — and stays
best-effort. On any machine where the art engine doesn't come up, the game is
still fully playable on pre-baked art.
