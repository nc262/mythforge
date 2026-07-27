# Session Handoff — pick up here (2026-07-23)

## ▶ STATE AS OF THE BAKE SESSION — THE GREAT BAKE IS DONE

**B1–B7 complete. All six worlds are poured, verified, zipped and exported.**
Full numbers in [AssetBake.md](AssetBake.md); the section below is the original
plan, kept for context.

- **Six** shipped worlds now, not four: the four originals plus **fimbulreach**
  (Norse saga) and **brasshaven** (gaslamp steampunk), both added mid-session at
  the Director's call because no built-in world covered those families.
- ~1 800 images, 7 390 catalogue entries, 1.4 GB of zips, ~11 h of GPU.
- `dist/Mythforge.exe` = **1.6 GB**, all six bundled, **copied to the Desktop and
  verified byte-for-byte** (the sandbox gotcha in §3 is real — it needs
  `dangerouslyDisableSandbox` twice: once to copy, once to prove it survived).
- Every world: 0 truncated PNGs, 0 catalogue entries with a missing icon.

**If a future pour is interrupted, just run it again** — that is the whole point
of B4. `godot --headless --path godot res://tests/bake_worlds.tscn` skips every
world already POPULATED and every image already on disk, and re-uses the stored
seed rather than re-asking the model. Proven by killing it mid-pour.

**The baked zips are NOT in git** (Director's call): `godot/baked/*.zip` is
gitignored and they ship as **release assets**, because the exe bundles them at
export and 1.4 GB per bake would bloat the repo forever. The four that were
tracked have been untracked (files untouched on disk). **A fresh clone therefore
exports an exe with no pre-baked worlds** until you re-bake or drop the release
zips into `godot/baked/`.

**One leftover to clean up when you're happy with the build:** the pre-bake packs
are renamed, not deleted, at
`%APPDATA%\Godot\app_userdata\Mythforge\worlds\<id>.prebake` (four dirs, ~300 MB).
They were the fallback if the pour had to be abandoned. The old zips are likewise
parked in the session scratchpad. Both are now redundant — the new zips are in
`godot/baked/` and verified.

## ▶ Packaging: the one-click installer (`installer/`)

New this session. A friend downloads one `Mythforge-Setup.exe`, clicks through,
and everything configures itself — no Python, no git, no manual downloads.
It is a **thin wrapper over `scripts/install.ps1`**, which already did the hard
parts (GPU detect → CUDA/ZLUDA/none, Ollama + models, ComfyUI + matting node +
SDXL, the app venv). The new code adds only the Godot client download, the
`model_endpoints` seeding, and runtime orchestration.

- `mythforge.ps1` — the only thing a player runs. Self-heals (bootstraps if
  unconfigured), starts Ollama → backend → image stack on loopback, seeds the
  two endpoint rows, launches the game, tears it all down on quit.
- `bootstrap.ps1` — first-run download & configure; idempotent, doubles as repair.
- `Mythforge-Setup.iss` — the Inno Setup one-click wrapper.

**Verified:** both scripts parse clean; the endpoint-seed POST is idempotent
(dedupes on `base_url` — added zero rows against the live backend).
**NOT yet verified, and it matters:** a full first-run on a clean machine, the
NVIDIA/CUDA path (this box is AMD), compiling the `.iss` (needs Inno Setup 6),
and code-signing for SmartScreen. See [installer/README.md](../../installer/README.md).

Also fixed this session, off the GPU path (UIPolish Round 5 Tier 0):
**B3** (World Forge failed *every* time — the worldsmith envelope was never
unwrapped, so `name` was always empty; one `Api.worldsmith()` helper fixes all
four call sites), **B4** (a failed strike now stays on the anvil with a live
retry instead of dumping the player back to the pillars), and **B5** (the
Campaign Shelf's cards are real `_big_card`s bound to their tale — the old ghost
button called `_open_adventure_forge()` with no arguments and threw the chosen
tale away). `click_driver` now has a **main-menu station** that guards all of it.

## ▶ ORIGINAL PLAN: The Great Bake (B1–B5)

Director approved 2026-07-23: **build the bake, then pour it.** Full plan and
numbers in [AssetBake.md](AssetBake.md); the *why* is in
[Performance.md](Performance.md) §7 (live art generation is what starved the
narrator down to 67 % GPU).

Order, and do not reorder — B4 protects B5:

1. **B1 — `_forms()` past weapon/armor.** `world_compiler.gd:838` iterates
   `["weapon", "armor"]`; the game has 13 slots (`Rules.EQUIP_SLOTS`). Add
   `<slot>_forms` to the seed schema (`world_compiler.gd:468`) and to `_forms()`.
   This is the unblocker for everything, and it also kills the eleven identical
   grey diamonds on the Gear tab.
2. **B2 — ask the seed for 10 materials and 10 treatments.** Verify the 8B still
   returns usable asset language; the 3B provably cannot (it returned
   *sharpening stones* for weapon forms — see §3 gotchas below).
3. **B3 — handcrafted fallback forms per slot in `data/tables.json`**, so a weak
   model or a failed seed can never ship another 33-PNG world (`everyday` today).
4. **Enchantment icon overlays — DECIDED: in scope, before the pour.** Rarity is
   already a draw-time glow; treatments currently touch names and stats only, so
   10 enchantments × 900 bases would all render identically and the
   combinatorics would exist only on paper.
5. **B4 — make the bake resumable and idempotent.** Skip keys already on disk,
   checkpoint per form×material. Non-negotiable: the pour is ~6.5 h per world
   and a crash at hour five must not restart it.
6. **B5 — pour** all four worlds (~3 600 images, ~26 h), re-zip, re-export.
   Also bake vendor stock icons in the same pass (Performance §7 A1) — they are
   a constant in `tables.json` and they are the exact jobs that half-offloaded
   the model.

Cheap parallel win while the pour runs: **11 empty-slot silhouettes** — 11
images, not 900, and the Gear tab stops looking broken immediately.

**Before any of it:** read [UXAudit-Round5.md](UXAudit-Round5.md). The Round-5
blocking tier (B1–B8 in [UIPolish.md](UIPolish.md)) is still open — two panels
whose close controls have broken hit areas, a dead exit from the play screen, a
dead Campaign Shelf, and a World Forge that fails every time.

---

# Previous handoff (2026-07-22, second pass)

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
- ~~`godot/data/` is gitignored~~ — fixed: `!godot/data/` negates the broad
  `data/` rule, and bestiary/spells/tables/class_lore are now tracked.

---

## 4. Open items (consolidated — bugs first, per user's priority)

### Bugs / decisions awaiting the user
- ✅ **Tale/world flow** — decided (b) and built: The Campaign stage is now two
  steps, world → tale within it, with BACK returning to the world list. That also
  fixed built-in worlds showing only Free Roam (their stories live in
  `worlds.json`; the stage now uses the `Rules.world_stories` fallback) and the
  12-card cap that hid later worlds' tales entirely.
- **`everyday` world is sparse** — the 8B gave it only 2 weapon forms → 30 items,
  6 part icons. Reforge its assets or hand-author more forms if it should be richer.
- **Verify the bug-fix build in play** — confirm the taskbar icon, card pictures,
  mid-stream sheet, and that "loses the thread" is gone with the timeout + warm models.

### VS-1 backlog (the "First Impression" sprint the user was tracking)
1. ✅ Trust — save index + Continue
2. ✅ Regressions — minimap / tabs / world name
3. ✅ The Art Director
4. ✅ Opening never dies
5. ▶ **Handcrafted defaults + appearance (the big asset pass)** — world assets:
   done (World Compiler + baked worlds). Hero appearance: user confirmed it's
   still owed. Audit found the pipeline mostly built already — Appearance stage,
   portrait commission, and the Stage-A paper doll (Gear tab, 13 slots,
   re-render) all ship. The real hole was **identity**: banked heroes had no id
   and shared the forge's `heroprev` scratch key, so roster cards were blank and
   a hero could later play wearing a newer hero's face. Fixed in `bank_hero`
   (name-derived id + portrait copied to `hero-<id>`), guarded in the harness.
   Still open on this strand: heroes banked *before* the fix stay id-less until
   re-banked, and appearance is still free text — no structured look (hair/build/
   skin) driving the prompt.
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
