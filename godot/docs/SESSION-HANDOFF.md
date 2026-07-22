# Session Handoff — pick up here (2026-07-22)

Read this first when resuming. It captures the current state, the workflows, the
hard-won gotchas, and the open items. Deeper detail lives in the linked docs.

---

## 1. What this build is, right now

A single-player desktop AI-RPG (Godot 4.7 client + local FastAPI/Ollama/ComfyUI
backend). The big arc of the last few sessions was the **World Compiler** — a
world is now a *compiled game package* (world-true items, creatures, NPCs, art),
not just data. As of this session the game **ships four worlds already baked**
and **has no login**.

### Shipped and working
- **World Compiler** (`godot/autoload/world_compiler.gd`) — S1–S10 + Reforge,
  compiles a world to POPULATED. See [WorldCompiler.md](WorldCompiler.md).
- **Per-material item art** — one matted AAA icon per (form × material), ~60/world;
  rarity is a draw-time glow. Verified world-true (driftwood vs brine-iron differ).
- **Catalogue visible in play** — `Art.item_tex_for` renders material-true icons +
  rarity glow in the inventory; loot rolls real items via `Compiler.roll_item`;
  a new hero is armed from the world catalogue (`Compiler.kit_for`).
- **Four pre-baked worlds ship in the exe** as zips under `res://baked/`, unpacked
  to `user://worlds/` on first run by `Compiler._ready`:
  - `saltmarsh` (Saltmarsh Reach — new default), `embervale`, `neonspire`, `everyday`.
  - Records in `godot/data/worlds.json`. Zips in `godot/baked/*.zip`.
- **No login** — `AUTH_ENABLED=false` on the backend (pm2 env + supervisor);
  `Api.auth_ok()` skips the login screen. Flip to `true` to host for friends.
- **Background compile** — forging a NEW world (campaign forge) fires
  `compile_seed` unawaited: play starts after worldsmith, the world fills in behind.
- **Bug-fix pass (this session, latest exe on Desktop 18:05):** app icon, world/hero
  card art, sheet/inventory openable mid-stream, and the "storyteller loses the
  thread" fix (180s SSE timeout + Ollama `KEEP_ALIVE=30m` / `MAX_LOADED_MODELS=2`).

---

## 2. Workflows (how to build / run / test / bake)

**Godot binary:** `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64_console.exe`

- **Harnesses (headless, test_mode, no backend):**
  `<godot> --headless --path godot res://tests/ui_playthrough.tscn` (mechanics +
  MIL + compiler data) and `res://tests/click_driver.tscn` (every screen clickable).
  **Both must stay green** on any change. They take ~40–150s each.
- **Export the exe:** `<godot> --headless --path godot --export-release "Windows Desktop"`
  → writes `dist/Mythforge.exe` (~443 MB now, four worlds bundled).
- **Copy to Desktop** — **MUST use `dangerouslyDisableSandbox: true`** (see gotchas).
  A running game locks the Desktop exe; the user must close it first.
- **Bake a world into the shippable set:** compile it (real backend+GPU) then
  `python scripts/bake_zip.py <src_world_id> <ship_id> "Name"` → `godot/baked/<id>.zip`,
  add it to `worlds.json`, re-export. `tests/bake_worlds.gd` bakes all built-ins.
- **Live full compile (real GPU):** `res://tests/compile_live.tscn` (needs the
  backend up; auth is off so no login).
- **Backend:** pm2 (`odysseus-api`, `image-stack`, `ollama`, …). Restart with
  `pm2 restart odysseus-api`. Runs from `Code\mythforge` (NOT the dead `odysseus`).

---

## 3. Gotchas that cost real time — don't relearn these

- **Desktop copy is sandboxed away.** `C:\Users\cptahabb\Desktop` is outside the
  project, so a normal `cp`/`Copy-Item` to it lands in a throwaway overlay: the
  copy "succeeds", `Test-Path` says true, then the file is gone. **Always copy to
  the Desktop with `dangerouslyDisableSandbox: true`, and verify with another
  sandbox-off call.** `dist/Mythforge.exe` inside the repo is always real.
- **Re-export after ANY client change.** The user tests the Desktop exe, not the
  Godot source; `godot/**` changes are invisible until you `--export-release` +
  copy. Backend-only (Python) changes reach them via the running backend.
- **The local LLM on this box is slow (~40–105s/call)** and worldsmith is
  multi-call — a full new-world forge is inherently minutes. Not a bug; it's the
  hardware. The 8B is the quality/narration model; the 3B (`studio_fast_model`
  pin = `llama3.2:3b`) is for worldsmith/extractors. The 3B is too weak for the
  compiler's asset language ("weapon forms" came back as *sharpening stones*), so
  the compiler stays on the 8B.
- **Seed-stage LLM requirements:** `/api/characters/studio/complete_json` MUST be
  in app.py's `_TIMEOUT_EXEMPT_PREFIXES` AND called with `json_mode=True` + a high
  token ceiling, or worlds silently fall back to generic content. A world's
  `generated:false` flag is the signal this regressed.
- **App runs on ComfyUI-ZLUDA (AMD RX 7900 GRE):** cuDNN off
  (`TORCH_BACKENDS_CUDNN_ENABLED=0`) or VAEDecode dies.
- **`godot/data/` is gitignored** by a stale broad `data/` rule — the game's static
  data (worlds.json, bestiary…) isn't tracked; exports still ship it from disk.
  A task chip is open to fix the `.gitignore`.

---

## 4. Open items (consolidated — bugs first, per user's priority)

### Bugs / decisions awaiting the user
- **Tale/world flow** *(needs a decision, then build)* — user wants to pick a tale
  then choose the world it plays in. Tales are currently authored per-world, so
  this is a flow change: either (a) world-agnostic tales the GM re-skins, or (b) a
  two-step "world → tale within it". Ask before rebuilding `adventure_forge._stage_campaign`.
- **`everyday` world is sparse** — the 8B gave it only 2 weapon forms → 30 items,
  6 part icons. Reforge its assets or hand-author more forms if it should be richer.
- **Verify the bug-fix build in play** — confirm the taskbar icon, card pictures,
  mid-stream sheet, and that "loses the thread" is gone with the timeout + warm models.

### VS-1 backlog (the "First Impression" sprint the user was tracking)
1. ✅ Trust — save index + Continue
2. ✅ Regressions — minimap / tabs / world name
3. ✅ The Art Director
4. ✅ Opening never dies
5. ▶ **Handcrafted defaults + appearance (the big asset pass)** — the World
   Compiler + baked worlds ARE this for *world* assets (done, shipped). The
   "+ appearance" half — the player HERO's own rendered portrait/look — is the
   older Character Render strand and is NOT part of the compiler work. Clarify
   whether #5 is done or still owes hero-appearance.
6. Flicker, instrumented
7. Dialogue identity — see [Dialogue.md](Dialogue.md)
8. Forge completion ritual
9. World Library

### Deeper (not started)
- **Ship weight** — ~320 MB of world zips are in git history + a 443 MB exe. If
  that's a problem, move baked worlds to Git LFS or a release artifact.
- Rest of the standing backlog: [Backlog.md](Backlog.md), [KnownIssues.md](KnownIssues.md),
  [Roadmap.md](Roadmap.md), [TechnicalDebt.md](TechnicalDebt.md).

---

## 5. Fast orientation for a fresh session
1. Read this + `MEMORY.md` (auto-loaded) + `CLAUDE.md`.
2. `git log --oneline -30` — the last ~25 commits are this session's compiler +
   baked-worlds + bug-fix work.
3. Confirm the stack: `pm2 ls`; backend `:7000`, bridge `:8101`, comfy `:8188`.
4. Run both harnesses green before changing anything.
