# Playtest #1 — triage, root causes, and the implementation plan

Director's hands-on pass, ~10 minutes, 2026-07-21. Treated as a QA report.
Every claim below was checked against the code before being written down.

---

## 1. Root causes found (evidence, not guesses)

### A. Continue lost the adventure — **root cause identified**

`main_menu._refresh()` only offers Continue when the saved adventure id is
present in `_templates`:

```gdscript
_templates = await Api.list_characters()          # → GET /api/presets/templates
if last is Dictionary and _templates.any(func(c): return str(c.get("id")) == str(last.get("id"))):
```

`list_characters()` returns **preset templates**, not the player's adventures.
An adventure forged from a *custom* world/campaign has an id that never appears
in that list, so Continue is silently suppressed or points at nothing — while
the state itself is safe on the server under `state/<cid>/…`.

**The save data was probably never lost.** The *index* is wrong: the game has no
first-class "my adventures" record, so it infers one from a template list.

**Fix direction:** a real save index (`_global.adventures`) written at adventure
start and touched on every autosave, holding `{id, name, world_id, hero, level,
day, updated_at}`. Continue reads the index, not the template list. Add a
"Resume" list so more than the single most-recent tale is reachable.

**Autosave audit:** `save_kind` already debounces + retries and covers sheet /
inv / clock / combat / world / cast / lore / quests. What is *not* consistently
written: creation-time records (a forged world/GM/campaign lands in `_global`,
but no adventure record), and there is no `updated_at` anywhere, so "latest
valid autosave" is not currently expressible.

### B. Flicker — **not one bug; the remaining sources are named**

Three prior fixes were real (art-storm rebuilds, one-frame double-draw, the
7–12 Hz candle). What the screenshots now show is different and mostly
**layout**, not rendering:

1. **The minimap overlaps the header** (my regression, Batch C). It is added to
   `Game` with absolute offsets `(14,12)–(204,136)`, on top of the `Margin/Split`
   tree, so it covers the "Free Roam" title → the screenshot reads "ree Roam".
   Anything drawn over reflowing text will also appear to shimmer.
2. **`_render_sheet()` still rebuilds a RichTextLabel wholesale** on many
   triggers. The signature guard I added stops *identical* repaints, but any
   HP/gold change rebuilds the entire panel including its image.
3. **Streaming appends re-layout the thread every delta**, which re-wraps text
   and can jitter the scroll.

**Fix direction:** stop guessing — land an instrumented `--flicker-probe` mode
that logs per-frame `queue_redraw`/rebuild counts per node for 10 s, then fix
what the numbers name. Do the minimap reparent first (certain, cheap).

### C. "An unrelated image appeared" — **root cause identified**

Three separate call sites POST to `/api/characters/studio/generate`:

| Caller | Path |
|---|---|
| `art_cache._pump()` | the single-flight queue, one image at a time |
| `game.gd:1806` `_conjure_scene()` | **bypasses the queue** |
| `game.gd:1849` `_repaint_scene()` | **bypasses the queue** |

So a scene repaint can run *concurrently* with a queued portrait or item icon
on a single-GPU ComfyUI. Concurrent jobs on one backend are exactly how the
wrong picture lands in the wrong frame. The photo of a woman with a form is
almost certainly another request's result surfacing in the scene slot.

**Fix direction:** one door. Every generation goes through `Art.ensure`, which
already has the priority lane; scene art becomes `Art.ensure_scene(key, prompt,
front=true)`. No caller may touch `/generate` directly (enforce in the harness,
like the hard-cuts law).

### D. "GM falls silent" at the opening — **partial cause**

`_on_done` prints that line whenever the accumulated reply is empty. There is
**no retry for an empty reply** — the only retry in the pipeline is the
*language-drift* retry. A first-token timeout or a model hiccup therefore ends
the adventure's opening in a dead bubble.

The playtest also shows the wait ran past 20 s (the reassurance line appeared),
which means the local model was genuinely slow — plausibly because **ComfyUI was
generating concurrently on the same GPU** (see C). The two bugs compound.

**Fix direction:** an empty/failed turn retries once automatically (silently,
like the drift retry), then offers a visible "Ask again" affordance instead of
a dead end. Never leave the opening scene empty.

### E. Heritage "floating purple placeholder" — **root cause identified**

`_stage_heritage()` builds a 256×256 empty `TextureRect` plus an empty
`RichTextLabel` (280×90) *before* any heritage is chosen and before any art
exists. Those are themed rectangles with nothing in them — the purple box.
Art is then **generated at runtime, per race, per world**, which is both slow
and unnecessary for a fixed set of nine heritages.

**Fix direction:** ship static heritage plates with the game; runtime generation
only for the player's own hero. Never render an empty art frame — show the
plate, or show nothing.

### F. Equipment placeholders (staff → star, leather → bag)

`MythCard`/`MythSocket` fall back to `MythIcon.resolve(glyph)`, which returns
**`"sigil"` (a star) for anything unmapped**, and the pack glyph for bags. So
until `item-<slug>.png` finishes generating, every item wears a wrong icon.

**Fix direction:** a shipped icon set for the common item vocabulary (the vendor
tables are known: weapons, armour, potions, food, general), keyed by
`Rules.item_type` + name. Generation reserved for genuinely unique loot. Until
art exists, show the *type* icon (sword/shield/potion), never a star.

### G. Character render gender/appearance mismatch

`_body_prompt` sends race + class + world fashion + worn gear — but **never the
appearance the player wrote** (`extra.appearance` is used for the *portrait*
only, at creation time, and is not stored on the sheet). So the full-body render
has no idea the hero is a green-haired female half-elf.

**Fix direction:** persist `appearance` and `style` onto the sheet at creation;
feed both into every later render (body, portrait re-strike). Also add explicit
sex/build terms, since diffusion models default to male for "druid, leather".

### H. Raw engineering string in the UI (found while reading)

`character_screen._hero_panel()` renders
`str(GameState.character.get("world_id","")).capitalize()` — so the custom world
id `cw-elyrien-or-6v` displays as **"Cw Elyrien Or 6v"** next to the hero's
name. Straight MIL §6 violation; the world's *name* must be resolved.

### I. Tab labels clipped — **my regression**

Fixing the off-screen-tab bug (click-driver) I made the nine tabs share the rail
width with `clip_text = true`. Result: "Chronicle" → "Chronic", "The Table" →
"The Tab". Correct fix is a smaller tab font + shorter labels, or a two-row
rail — never silent truncation.

---

## 2. Scope check — three of these are features, not polish

The standing instruction is that VS-1 must not become a feature sprint. These
items are genuinely new systems and are **proposed for VS-2**, not this sprint:

| Item | Why it's a feature |
|---|---|
| #5 World Library | a new browsable screen with stats, links, campaign counts |
| #9 Campaign Forge depth (18 new inputs) | a redesigned multi-stage flow + prompt architecture |
| #8 Appearance editor | a structured character-builder UI replacing free text |
| #6 Main-menu IA regrouping | navigation redesign touching every entry point |

They are all correct calls, and they're recorded in [VerticalSlice.md]. Doing
them *inside* VS-1 would double the sprint and delay the bug fixes that are
currently making the build feel unfinished. **Recommendation: VS-1b (below)
ships the fixes; VS-2 takes the four features with proper design docs.**

---

## 3. Implementation batches, dependencies, and order

Ordered by *risk-adjusted value*: certain-cause fixes first, instrumented
investigations second, content pipelines third, features last.

### Batch 1 — Trust (do first; nothing depends on it, everything benefits)
**Issues 1, 11.** The save index + Continue.
- `_global.adventures` record written at adventure start, touched by `save_kind`
  with `updated_at`.
- Continue reads the index; a "Resume a tale" list shows the rest.
- Newly forged campaigns/worlds appear immediately because the index is the
  source of truth, not a cached template list (fixes #11's refresh problem too).
- **Depends on:** nothing. **Blocks:** #5 World Library, #12 Tales (both want
  the same index).
- **Risk:** low — additive; existing state writes untouched. **Effort:** M.

### Batch 2 — My regressions (fast, certain, visible)
**Issues 2 (partial), 13, plus H and I.**
- Minimap reparented into the layout (or moved opposite the header) — ends the
  "ree Roam" overlap and the map/free-roam collision.
- Tab rail: smaller type, real labels, no clipping.
- World *name* resolved instead of the raw id.
- Map: never render before its chart texture exists (placeholder frame).
- **Depends on:** nothing. **Effort:** S.

### Batch 3 — One art door (unblocks the worst mystery)
**Issues 15 (unrelated image), 13 (slow map), 14 (partly).**
- All `/generate` traffic through `Art.ensure`; scene art gets the priority lane.
- Harness law: no direct `/generate` outside `art_cache.gd`.
- **Depends on:** nothing. **Blocks:** Batch 5 (placeholders need a predictable
  pipeline). **Risk:** medium — touches the streaming path. **Effort:** M.

### Batch 4 — The opening must never die
**Issue 14.**
- Empty/failed reply retries once silently; then a visible "Ask again".
- Adventure opening gets a guaranteed fallback beat if the model never answers.
- **Depends on:** Batch 3 (GPU contention is a contributing cause).
- **Effort:** S–M.

### Batch 5 — Handcrafted defaults, generation only where unique
**Issues 7, 16, and the "prefer handcrafted" directive.**
- Ship heritage plates (9) + a common-item icon set keyed to the vendor tables.
- Type-correct fallback icons; never a star for a staff.
- Persist `appearance`/`style` on the sheet; every render uses them (fixes G).
- **Depends on:** Batch 3. **Effort:** L (asset generation + wiring, one pass).

### Batch 6 — Flicker, instrumented
**Issue 2 (remainder).**
- `--flicker-probe`: per-node redraw/rebuild counts over 10 s.
- Fix by the numbers; re-probe to prove it.
- **Depends on:** Batch 2 (removes the known-certain cause first, so the probe
  measures what's left). **Effort:** M, uncertain tail.

### Batch 7 — Dialogue identity
**Issue 3.**
- Speaker nameplate + portrait + world-themed frame on NPC speech, driven by the
  `[[npc]]` cast the engine already keeps.
- **Depends on:** Batch 5 (portraits), Batch 3 (art pipeline).
- **Effort:** M. *This is the single biggest perceived-quality gain remaining.*

### Batch 8 — Forge flow completion
**Issues 4, 10, 12.**
- World Forge: a real forging sequence (world-aware, occasionally funny), then
  **open the new world's overview**, never return to the forge.
- Same "show me what I made" rule for Campaign and GM.
- From Begin New Adventure, return with the new item selected.
- Tales decoupled from a single world.
- **Depends on:** Batch 1 (the index), and #5's overview page is its landing
  target — so a *minimal* overview ships here and the full Library is VS-2.
- **Effort:** M–L.

### VS-2 (separate sprint, design docs first)
Issues **5, 6, 8, 9** — World Library, menu IA, appearance editor, Campaign
Forge depth. Plus #15's Sheet/Journal reorganisation, which is IA work of the
same kind.

---

## 4. Proposed order

```
1 Trust (save index + Continue)        ← nothing depends on it; restores faith
2 My regressions (minimap/tabs/name)   ← S, certain, immediately visible
3 One art door                         ← unblocks the wrong-image mystery
4 Opening never dies                   ← needs 3
5 Handcrafted defaults                 ← needs 3; largest asset pass
6 Flicker, instrumented                ← needs 2; measure, then fix
7 Dialogue identity                    ← needs 5; biggest quality gain
8 Forge flow completion                ← needs 1
--- ship, playtest #2 ---
VS-2: World Library · menu IA · appearance editor · Campaign Forge depth
```

**Why this order:** batches 1–2 are certain-cause and cheap, and they repair the
two things that most undermine trust (lost progress, a broken-looking screen).
Batch 3 is the keystone — it explains the wrong image, contributes to the slow
map and to the silent GM, and every later art batch assumes one predictable
pipeline. Features wait until the build stops feeling broken.

**Rule carried forward:** after each batch, both harnesses must stay green, and
the click-driver gains coverage of whatever the batch touched.
