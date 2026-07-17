# Sprint: The First Complete Experience — Design & Roadmap

Status: **DESIGN — not yet approved for implementation.** Author: acting Game/Technical/UX/AI
Director. Scope: Issues 1–6 from the sprint brief. This doc is the plan; code follows approval.

---

## 0. Executive summary — the two spines

Six issues were briefed. They are **not** six independent features. Analysed against the real
codebase, they collapse onto **two missing subsystems plus two independent tracks**:

| Spine / track | Serves | Nature |
|---|---|---|
| **A. World Skin system** — a per-campaign visual descriptor the World Forge emits, resolved by every surface | Issue 2 (theming) · Issue 6 (skill-tree presentation) · look of Issue 3 & 1 · materials for Issue 5 | **Keystone.** Build once, everything inherits. |
| **B. The Living Book** — an aggregation + book-UI layer over data we already persist | Issue 1 (Chronicles) · Issue 3 (Lore Book) | Two views of one subsystem. |
| **C. Language Integrity Guard** | Issue 4 | Independent, cheap, high-impact correctness. |
| **D. Character Rendering** | Issue 5 | Independent, content-heavy, XL. Stage it; defer true 3D. |

**The core architectural insight:** theming today is hardcoded to three built-in worlds
(`Ui.PALETTES` has exactly `arcane`/`neonspire`/`everyday`; every custom `cw-…` world falls back to
fantasy). `Ui.material_sb()` only knows `steel/leather/brass/oak`. `Art.world_flavor()` maps two ids
else `"high fantasy"`. **The engine has no concept of a per-campaign visual language.** The World
Forge already collects the exact inputs needed to derive one (`fields`: Magic/Technology/Era/Beasts/
Tone). Issue 2 is not "add cyberpunk styling" — it is "introduce the missing Skin abstraction and
route every surface through it." Once that exists, Issue 6 is a renderer swap, Issue 3/1 inherit a
look, and Issue 5's themed materials have a source of truth.

**Recommended order (detail in §11):** C (language) → A (skin) → B (living book) → 6 (skill tree)
→ 1-menu polish → D (character, spike only). Rationale: ship the cheap correctness win, then the
keystone that unblocks the most, then the biggest immersion payoff, then the skin-dependent
features, and treat true-3D as a deferred spike, not a sprint commitment.

---

## PART I — PER-ISSUE ANALYSIS

Each issue is analysed for: **root cause · architecture · engine / AI / UI / backend changes ·
dependencies · complexity · risks.** Complexity scale: **S** ≈1–2 dev-days, **M** ≈3–5, **L** ≈1–2
weeks, **XL** ≈3+ weeks.

---

## ISSUE 4 — LLM language drift (analysed first: it gates player trust)

### Root cause
Confirmed by reading `prompt_composer.gd` and `api_client.stream_chat`:

1. **No language is ever pinned.** Neither `PROTOCOL`, `envelope()`, nor `compose_world_gm()`
   states an output language. Small quantised multilingual Ollama models have Chinese/other-script
   mass in their base distribution; with nothing anchoring English they drift — especially after a
   non-Latin token seeds the switch (a stylised name, a recalled beat, a unicode glyph).
2. **Recency + context growth.** The envelope prepends a large context block; the persona system
   prompt sits far back in history. As the session grows, the language-establishing tokens get
   buried. There is no persistent, late-position language anchor.
3. **Zero detection or repair.** `stream_chat` streams tokens straight to the visible bubble
   (`_on_delta`). By the time drift is visible, the player has already seen it. Nothing detects,
   retries, or logs.
4. Contributing: backend sampling temperature (not set per-request here) and tag-parser tolerance
   (a drifted reply still gets parsed, so garbage can reach mechanics).

**Primary cause = (1). (2)+(3) explain why it isn't self-correcting.**

### Architecture
Add a **language contract** to the campaign and a **guard** around the stream. The guard is a small
state machine on the *display* side, not the model side, so it works regardless of backend.

### Changes
- **AI / prompt:** store `world.language` (default `"English"`), set at Campaign/World Forge.
  Append to `PROTOCOL` tail (last, highest-recency position): *"Write ALL narration and dialogue in
  {language}. Never switch languages, even if a name or quote suggests otherwise."* Also add the
  one-liner to `compose_world_gm()` so it's in the persona too (belt and suspenders).
- **Engine (`api_client` / `game.gd`):** buffer the first ~60 visible chars (or up to first
  newline) before revealing the bubble — imperceptible latency, but lets the guard inspect the
  opening. A `LanguageGuard` helper scores the buffer: ratio of CJK/Cyrillic/etc. codepoints vs the
  target script. If over threshold → **abort display, don't show it, auto-retry once** with a
  stronger prepended anchor (and lower temp if backend exposes it). On second failure, show a
  graceful degraded line ("*the storyteller gathers their thoughts…*") and re-issue. **Log every
  incident** (`user://logs/lang_drift.log`) with the offending snippet.
- **UI:** a Settings + Forge control for campaign language (default English). No player-facing error
  ever — detection/retry/repair are silent.
- **Backend:** none required if temperature can't be set per-call; optional ≤3-line tweak to accept
  a `temperature`/`stop` passthrough on `/chat_stream` (nice-to-have, not required).

### Dependencies
None. Can ship standalone immediately.

### Complexity: **S–M** (≈2–3 days). ### Risks
- **Low.** Main risk: over-eager detector aborting legitimate content (e.g. a deliberately
  multilingual world). Mitigate: threshold tuned high, scoped to the opening buffer, single retry,
  and the campaign-language setting lets a bilingual world opt out.

---

## ISSUE 2 — World theming (the keystone: the World Skin system)

### Root cause
Theming is keyed to a **fixed enum of three built-in worlds**, with fantasy as the universal
fallback:
- `Ui.PALETTES` = `{arcane, neonspire, everyday}`; `_world_card`/`apply` do
  `PALETTES.get(wid if has(wid) else "arcane")` → **every forged `cw-…` world renders fantasy.**
- `Ui.material_sb(kind)` only produces `steel/leather/brass/oak` (fantasy plates for `MythButton`).
- `Art.world_flavor()` → two ids else `"high fantasy"` (so generated art is fantasy-styled too).
- Inventory/sheet type-glyphs, `MythIcon` shapes (anvil/scroll/banner), and `RARITY` names are all
  fantasy-authored constants.

There is **no per-campaign visual descriptor** anywhere in the data model.

### Architecture — the **World Skin**
Introduce a `skin` object, stored on the world (`world.skin`), **derived deterministically** from
world attributes with optional LLM refinement of palette hexes only:

```gdscript
skin = {
  "id": "cyber",                         # skin family: fantasy|cyber|space|steam|pirate|<custom>
  "palette": { night, surface, ink, accent, accent2, danger, ... },  # hex overrides for Ui
  "materials": { "primary":"glass", "secondary":"carbon", "accent":"neon" },  # MythButton plates
  "surface_family": "holographic",       # selects a procedural texture generator in skin.gd
  "icon_set": "cyber",                   # MythIcon variant map
  "flavor": { "currency":"credits", "map":"holo-map", "book":"datapad", "pack":"grid" },
  "art_style": "cyberpunk neon concept render, volumetric haze",  # Art prompt suffix
}
```

**Derivation is deterministic** (`Skin.derive(world)`): map `world.kind` + `fields.Technology` +
`fields.Tone` → a skin family (`Starfaring`→space, `Neon cyberpunk`→cyber, `Steam & clockwork`→
steam, `Age of sail`→pirate, else fantasy). The LLM (worldsmith) may *refine* palette hexes and the
`art_style` string, but the game never depends on the LLM for a valid skin — a deterministic default
always exists. This is the load-bearing robustness decision.

### Changes
- **Engine (new `skin.gd` responsibilities / new `Skin` autoload):**
  - `Skin.derive(world) -> Dictionary` (deterministic) and `Skin.for_world(world)` (cached, prefers
    `world.skin`, else derives).
  - `Ui.apply(world)` takes the **world** (not just id): installs palette from `skin.palette`,
    active material family, icon set, surface family. `Ui.PALETTES` demoted to fallback seed.
  - Extend the procedural texture set in `skin.gd` (already has `forged/leather/brass/wood`) with
    **glass/holo, carbon, titanium, copper, canvas/rope** generators; `material_sb(kind)` resolves
    against the active skin's material family.
- **UI:** `MythButton`, `MythChoiceCard`, `MythEnvironment`, `MythIcon`, inventory/sheet/merchant/
  map/journal/skill-tree all read palette + material + icon-set from the active skin instead of
  hardcoded values. `MythIcon` gains per-set variants (or a `set`-aware draw path); `MythIcon.resolve`
  becomes skin-aware. Flavor nouns (currency/map/pack/book) come from `skin.flavor`.
- **AI / worldsmith:** worldsmith `mode:"world"` output gains an optional `skin` block (palette +
  art_style). Prompt asks for a colour palette + one-line art direction. Deterministic derive fills
  any gap.
- **Backend:** none required (skin rides the existing `cworlds` state blob). Optional: worldsmith
  prompt update lives backend-side if that's where the template is.

### Dependencies
World Forge (shipped). Blocks: Issue 6 presentation, and improves Issues 1 & 3 look.

### Complexity: **L** (≈1.5–2 weeks — mostly the mechanical thread-through of ~10 surfaces + new
texture generators). ### Risks
- **Medium.** (a) Generated palettes can be low-contrast/illegible → **contrast-clamp** every
  derived palette against accessibility minima (reuse the DesignSystem a11y rules). (b) Scope creep
  across many files → do it as a strict `Ui.c()/material_sb()/icon` routing change, no per-surface
  bespoke art. (c) Existing three built-in worlds must be re-expressed as skins so nothing
  regresses — treat them as the three reference skins and snapshot-test them.

---

## ISSUE 3 — Generated Lore Book  &  ISSUE 1 (part) — Chronicles as a history book

These are **one subsystem, two lenses.** Lore Book = the *world's* encyclopedia (authored +
discovered). Chronicles = the *campaign's* played history. Both are "an illustrated book that writes
itself from data we already persist, generating art on demand."

### Root cause
The **data already exists but is never aggregated or surfaced as a book**:
- `Chronicle` autoload persists `transcript` (60 turns), server **beats** (timeline), **codex**
  (cast), **quests**. World state carries **locations/cast/creatures/stories**. `Art` cache already
  keys **npc-/beast-/map-/hero-/chart-/world** art.
- Chronicles menu today just lists `dm-` saves — **redundant with Continue** (confirmed: Continue
  jumps to latest, Chronicles lists saves; same data, two entry points).
- No layer assembles these into per-campaign encyclopedia entries; no book UI; no accretion of
  "discovered" lore during play.

### Architecture — the **Living Book / Codex model**
A `LoreBook` aggregation layer + a paginated book UI, both skin-styled.

- **Data:** a per-campaign `lore` state kind = `{ entries: [{ category, title, body, art_key,
  discovered_day, source }] }`. Categories map to the brief: history, kingdoms, cities, landmarks,
  religions, factions, guilds, bestiary, flora, resources, weapons/armor, magic/tech, NPCs,
  languages, maps, player-discoveries, journal, quest-history, legendary-battles.
- **Population, three sources:** (1) **World Forge seed** — the sealed world's locations/cast/
  creatures/stories become initial entries. (2) **Play accretion** — a new `[[lore category=…
  title=… ]]` tag (added to the PROTOCOL) lets the GM inscribe discoveries; the existing
  codex/quest extractors already produce structured NPC/quest entries to fold in. (3) **Chronicle**
  — beats → timeline, snapshots → chapters, combat logs → "legendary battles."
- **Art on demand:** entries request art through the existing `Art.ensure()` queue (portrait/
  creature/location prompts already exist), styled by `skin.art_style`.
- **UI:** `LoreBook` scene — a two-page spread (`MythEnvironment` "env-journal" backdrop), category
  tabs, illustrated entries, a campaign timeline, statistics, session history. Chronicles opens the
  **same** book scoped to played history; Lore Book (in-play, a toolbar button) opens it scoped to
  world knowledge. One scene, two entry contexts.

### Changes
- **Engine:** new `LoreBook` autoload (aggregation, dedupe, art requests) + `lore` state kind;
  seed on world seal; fold codex/quests/beats each `chronicle_updated`.
- **AI:** add `[[lore …]]` to the PROTOCOL (opt-in; missing tags never block play). Extractor
  prompts can gain a "notable world facts" pass reusing the codex endpoint.
- **UI:** `scenes/ui/lore_book.*` (paginated, skin-styled); Chronicles menu rebuilt to open it;
  in-play toolbar entry.
- **Backend:** none required (reuses `/memory`, `/codex`, `/quests`, `/generate`). Optional new
  extractor endpoint for "world facts" if we want richer auto-lore (nice-to-have).

### Dependencies
Soft-depends on **Skin** (for its look) and benefits from Chronicle (shipped). Independent of Skin
functionally — can be built greyscale then skinned.

### Complexity: **L** (≈1.5–2 weeks: aggregation is modest; the book UI + art choreography is the
work). ### Risks
- **Medium.** (a) Art queue saturation (one GPU also serves narration) → the existing single-flight
  queue already throttles; lore art is low-priority, lazy, cached. (b) LLM lore quality/consistency
  → entries are *appended*, canon is honored, dedupe by title; never block play on a lore call.
  (c) Redundancy resolution: **fold Continue into Chronicles' cover gallery** (each campaign cover =
  Continue button), removing the duplicate entry point.

---

## ISSUE 1 (remainder) — Main Menu AAA quality

### Root cause
Legibility and impact, not architecture. `MythButton` engraved type (dark fill + light shadow) can
fall below contrast minima on some material plates; type scale lacks a hero tier; the layout is a
vertical button stack without editorial hierarchy. The controls are already handcrafted (not
software widgets) after the last sprint — the gap is **typographic impact + contrast + composition**,
plus the Continue/Chronicles redundancy (resolved in Issue 3).

### Architecture
No new systems. A **type-scale + contrast pass** on `MythButton`/DesignSystem, a composition pass on
the title screen, and Chronicles becomes the illustrated book (Issue 3). Menu cards inherit the
active/last-played campaign's **Skin** for cover art and accent.

### Changes
- **UI:** raise display type scale + tracking for the title; enforce engraving contrast (light-on-
  dark fallback when a plate is dark); introduce editorial layout (hero title, primary trio, quiet
  secondary row); menu background = last-played world key art (skin-tinted). Continue folds into the
  Chronicles cover gallery.
- **Engine/AI/Backend:** none.

### Dependencies
Skin (for card theming) + Living Book (for Chronicles). ### Complexity: **M** (≈3–5 days).
### Risks: **Low** — pure presentation; snapshot-test the three reference skins.

---

## ISSUE 6 — World-adaptive skill trees

### Root cause
`skill_tree.gd` exists (the "Constellation of Destiny") but presentation is single-theme and the
underlying per-class **progression graph** is thin. The brief's requirement — deterministic
progression, themed presentation — is exactly the **Skin pattern applied to a data-driven graph**.

### Architecture
Split cleanly into **model** (deterministic) and **renderer** (skin-driven):
- **Model:** `data/skill_trees/<class>.json` — nodes (id, tier, cost, prereqs, effect), deterministic
  and identical across worlds. Effects resolve through existing Rules/sheet.
- **Renderer:** a `SkillTreeView` that lays out the graph and draws it in the active skin's idiom —
  runes/branches (fantasy), circuit/neural (cyber), constellations (space), gears (steam), nav-chart
  (pirate). Layout algorithm is shared; node/edge glyphs + background come from Skin.

### Changes
- **Engine:** per-class node-graph data + a deterministic unlock/respec resolver; presentation
  registry keyed by `skin.id`.
- **AI:** none (progression is engine-owned). **Backend:** none. **UI:** the themed renderer.
### Dependencies: **Skin (hard)** + a real progression model. ### Complexity: **L** (≈1–1.5 weeks;
the node graph content + one solid layout + N background styles). ### Risks
- **Medium.** (a) Authoring N class graphs is content work → ship 2–3 classes first, template the
  rest. (b) Presentation divergence must never fork the math → one resolver, presentation is pure
  view. (c) Respec/refund rules → keep deterministic and reversible.

---

## ISSUE 5 — Full 3D character

### Root cause
Not a bug — a **capability gap with a large content cost.** Today the sheet shows a 2D generated
`MythPortrait`. True live-equipment 3D requires: a rigged base mesh per body type, modular equipment
meshes with attachment sockets, **per-theme asset libraries** (fantasy/cyber/space/steam/pirate ×
weapons/armor/helmets/capes/cyberware), a `SubViewport` 3D render pipeline, and material theming.
The engine (Godot) supports it; the **assets do not exist** and are the dominant cost.

### Architecture — stage it, do not commit true-3D this sprint
- **Stage A (cheap, immersive now):** **layered 2D paper-doll.** Composite generated equipment art
  over the portrait at fixed slots (weapon/armor/helm/cape/shield). Equip → recomposite. Reuses the
  Art pipeline; themed by Skin. Delivers "equipment shows on the character" at ~M cost.
- **Stage B:** **equipment-aware portrait regeneration** — re-prompt the portrait including equipped
  items + skin style on major loadout change (cached per loadout hash).
- **Stage C (deferred, own milestone):** true `SubViewport` 3D with modular meshes + sockets +
  per-theme material sets. Gate on an asset pipeline decision (commissioned vs. generated-3D vs.
  store assets). This is XL and content-bound.

### Changes
- **Engine:** Stage A = a compositor in the sheet; Stage C = a 3D character scene + socket map +
  `SubViewport` (future). **AI:** equipment art prompts (Stage A/B). **UI:** sheet render swap.
  **Backend:** none (Stage A/B); asset hosting decision (Stage C).
### Dependencies: Skin (material/theme). ### Complexity: **Stage A = M**, **Stage C = XL**.
### Risks
- **High for Stage C**: content pipeline is the project's largest unknown; ZLUDA/GPU already shared
  with narration+image gen; 3D asset generation is immature. **Recommendation: build Stage A this
  sprint if capacity allows, spike Stage C only, do not commit true-3D as a sprint deliverable.**

---

## PART II — CROSS-CUTTING

## 7. Dependency graph

```
        (independent)                         (independent)
   ┌── ISSUE 4  Language Guard            ISSUE 5  Character render
   │   (ship first)                        Stage A (M) ──┐ Stage C (XL, deferred)
   │                                                     │ needs Skin(materials)
   │                                                     ▼
   └── ISSUE 2  WORLD SKIN  ◀── World Forge (shipped) ───┴──────────────┐
              │  (KEYSTONE)                                             │
              ├──────────────► ISSUE 6  Skill-tree presentation (hard dep)
              ├──────────────► ISSUE 1  Menu card theming (soft)
              └──────────────► look of ▼
        ISSUE 3 / ISSUE 1  LIVING BOOK  ◀── Chronicle/codex/quests (shipped)
              (Lore Book + Chronicles; folds Continue in)
```

## 8. Complexity summary

| Issue | Track | Complexity | Est. |
|---|---|---|---|
| 4 Language guard | C | S–M | 2–3 d |
| 2 World Skin | A (keystone) | L | 8–10 d |
| 3 + 1a Living Book | B | L | 8–10 d |
| 6 Skill tree | rides A | L | 6–8 d |
| 1b Menu polish | rides A+B | M | 3–5 d |
| 5 Character | D | M (Stage A) / XL (C) | 4–5 d / defer |

Sprint-committable ≈ **4½–6 weeks** for tracks C+A+B+6+1 (+ Stage A if capacity). Stage C is a
separate future milestone.

## 9. Risk register (top)

| Risk | Issue | Sev | Mitigation |
|---|---|---|---|
| Generated palettes illegible | 2 | M | Contrast-clamp all derived palettes vs a11y minima; three built-ins as reference skins |
| Skin thread-through = broad diff | 2 | M | Pure routing change through `Ui.c/material_sb/icon`; no bespoke per-surface art; snapshot tests |
| Over-eager language detector | 4 | L | High threshold, opening-buffer only, single retry, per-campaign language opt-out |
| Art queue saturation | 3,5 | M | Existing single-flight queue; lore/equipment art low-priority, lazy, cached |
| 3D content pipeline unknown | 5 | H | Stage A paper-doll now; Stage C spike only; do not commit true-3D |
| Skill-tree math forks per theme | 6 | M | One deterministic resolver; presentation is pure view |
| Menu regressions on built-ins | 1 | L | Re-express `arcane/neonspire/everyday` as skins + snapshot-test |

## 10. Milestones

- **M-A — Language Integrity (Issue 4).** Language contract + stream guard + retry/repair + log.
  *Exit:* forced-drift test never reaches the player; incidents logged; English guaranteed.
- **M-B — World Skin (Issue 2).** `Skin` autoload + deterministic derive + `Ui.apply(world)` +
  extended material/texture generators + all surfaces routed. *Exit:* a forged cyberpunk/space/steam/
  pirate world renders its own palette, materials, icons, currency, and art style end-to-end; three
  built-ins re-expressed as reference skins with no regression.
- **M-C — Living Book (Issues 3 + 1a).** `LoreBook` aggregation + `lore` kind + `[[lore]]` tag +
  paginated skin-styled book scene; Chronicles rebuilt on it; Continue folded into cover gallery.
  *Exit:* opening Chronicles/Lore Book feels like an illustrated history book that grew from a played
  session; art renders for entries.
- **M-D — Adaptive Skill Tree (Issue 6).** Per-class node graphs (2–3 classes first) + deterministic
  resolver + skin-driven renderer. *Exit:* same progression, five presentation idioms.
- **M-E — Main Menu AAA (Issue 1b).** Type-scale/contrast/composition pass; skin-themed cards.
  *Exit:* title screen reads "AAA RPG"; legibility verified in all reference skins.
- **M-F — Character Rendering (Issue 5).** Stage A paper-doll (committable); Stage C 3D **spike only**
  + asset-pipeline decision doc. *Exit A:* equipment shows on the character, themed. *Exit C:* go/no-go.

## 11. Recommended implementation order

1. **M-A Language guard** — cheapest, fixes a trust-breaking bug in the core loop, unblocks nothing
   but improves everything. Ship first.
2. **M-B World Skin** — the keystone; unblocks 6, improves 1 & 3. Highest architectural leverage.
3. **M-C Living Book** — biggest single immersion payoff; rides Skin's look, uses shipped data.
4. **M-D Skill tree** — now cheap because Skin exists; deterministic model + themed view.
5. **M-E Menu polish** — rides Skin + Chronicles; final coat before the character work.
6. **M-F Character** — Stage A if capacity; Stage C spike + decision, **not** a sprint commitment.

Rationale: front-load the correctness win and the keystone, sequence everything that depends on the
keystone behind it, and quarantine the one content-bound XL item so it can't sink the sprint.

## 12. Documentation updates (to land with each milestone)

- **`DesignSystem.md`** — new **§7 World Skin**: skin schema, deterministic derivation table
  (world attribute → skin family), material/texture families, contrast-clamp rule, icon-set variants.
- **`docs/WorldSkin.md`** (new) — the authoritative skin contract + how each surface resolves it.
- **`docs/LoreBook.md`** (new) — the `lore` kind, category taxonomy, three population sources, the
  `[[lore]]` tag grammar, art choreography.
- **`docs/AI.md`** — language contract, the drift guard state machine, incident logging.
- **`docs/rituals/SkillTree.md`** — model/renderer split; per-skin presentation idioms.
- **`docs/rituals/Chronicle.md`** (or extend Journal) — Chronicles-as-book; Continue folded in.
- **`FeatureMatrix.md` / `Roadmap.md`** — add M-A…M-F rows; mark true-3D (Stage C) as deferred.
- **`TechnicalDebt.md`** — record the character-render staging decision and the asset-pipeline open
  question.
- **`PRODUCT.md`** — the "first complete experience" quality bar this sprint targets.

---

## Open decisions for the Director (before implementation)

1. **Skin palette source:** deterministic-only (robust, ships now) vs. LLM-refined hexes
   (richer, adds a failure mode). *Recommendation: deterministic default always valid; LLM refines,
   never gated on.*
2. **Chronicles ↔ Continue:** confirm folding Continue into the Chronicles cover gallery (removes
   the redundancy the brief flagged).
3. **Language default:** English hard default with per-campaign override — confirm, or make it a
   first-class Forge choice.
4. **Issue 5 scope for THIS sprint:** Stage A paper-doll only + Stage C spike — confirm true-3D is
   deferred to its own milestone with an asset-pipeline decision first.
5. **Skill-tree launch classes:** which 2–3 classes lead (suggest Fighter, Wizard, Rogue).
