# Architecture Evolution — review & roadmap (2026-07-18)

**This is a review, not a rewrite.** The architecture is correct and is NOT
changing:

- **Godot owns all deterministic gameplay.**
- **FastAPI owns AI, persistence, memory, image generation, orchestration.**
- **The `[[tag]]` protocol is the ONLY way the AI requests deterministic state
  changes.** The AI may *suggest* presentation; it may never *alter* gameplay.

Everything below evolves working systems toward a modern AAA RPG shape while
preserving them. Each principle: **where we are → the gap → why it matters →
complexity → dependencies.** The milestone roadmap (§11) sequences them.

Baseline today: eleven autoload "system services" (`Mode` FSM · `Ui` skin ·
`Api` HTTP/SSE · `GameState` · `Rules` · `Tags` · `Composer` · `Combat` ·
`Chronicle` · `Art` · `WorldSkin`), JSON data tables in `data/*.json`, a
`[[tag]]` protocol as the sole AI→state channel, and one monolithic `game.gd`
view (~1.4k lines). The bones are good; the evolution is about seams, structure,
and richer structured context.

---

## 1. AI Character System — data-driven Character Resources

**Where we are.** NPCs are a *personality string* composed once (the GM persona
via `Composer.compose_world_gm`; companions as prose). `Chronicle`'s codex
extractor produces `{name, role, note}` and portraits generate on meet. World
descriptors carry an authored `cast` list.

**Gap.** No structured per-NPC resource: no goals, fears, relationships,
reputation, secrets, faction, emotional state, or memory references. The LLM
re-reads a prose blob each turn; relationships aren't modelled (KnownIssue: no
relationship stat).

**Evolve → `CharacterResource`.** A structured schema (persisted as an `npcs`
state kind, or typed `Resource`) with the briefed fields. The codex extractor
already fills name/role/note — extend it to accrete goals/relationships/secrets
over play (it's the same extractor pattern). `Composer` includes the *relevant*
NPC resources for the current scene as structured context, not a rebuilt blob.
Reputation/relationships become a small graph (already in FutureIdeas).

**Why.** Consistency (NPCs keep goals/secrets), unlocks reputation & relationship
systems, and shrinks the per-turn prompt. **Complexity L. Deps:** Chronicle
extractors, Composer, a persistence kind, and the Style Guide (§6) for tone.

## 2. Structured AI Output — presentation metadata (via tags)

**Where we are.** `[[tag]]` carries deterministic effects; prose carries
narration. `tag_parser` already collects *any* tag generically and strips them
from display. No emotion/tone/portrait/ambient/music/camera signal exists.

**Gap.** The engine can't react to the emotional beat — no portrait expression,
ambient cue, music swell, or camera push driven by the narration.

**Evolve → presentation-only tags.** This is the *natural* extension of the
existing protocol and honours the rule perfectly: add a class of tags the AI may
emit that touch **only presentation, never state** —
`[[mood tone=tense]]` · `[[portrait expr=grim]]` · `[[ambient sound=rain]]` ·
`[[music cue=dread]]` · `[[camera push=in]]`. `tag_parser` already parses them;
`game.gd` routes them to `Sfx` / `MythPortrait` / the backdrop — and a hard rule
in code: presentation tags can call presentation systems only. State tags stay
the sole gameplay channel.

**Why.** Emotional resonance and AAA reactivity, with zero risk to the
determinism guarantee. **Complexity M. Deps:** Tags (generic already), Sfx,
portrait system, Style Guide (§6) for the expression/sound vocabulary.

## 3. Component-driven gameplay

**Where we are.** Systems are cohesive singletons (`Combat`, `Rules`, `GameState`
procedures) — good separation of *logic* — but `game.gd` is a monolithic view
mixing chat, combat UI, sheet, shop, and forge, and entity behaviour isn't
reusable across entities (companions can't cleanly reuse "combat" or "inventory").

**Gap.** The god-script is the #1 structural risk; behaviours aren't attachable
components.

**Evolve, don't ECS-ify.** Full ECS would *replace* working systems (violates the
brief). Instead: (a) **split `game.gd`** into view scenes under the FSM
(`ChatView` / `CombatView` / `SheetView` / `ShopView`); (b) keep the autoloads as
named **system services** with clear boundaries (they already are
Inventory/Equipment/Combat/Skill logic); (c) introduce a lightweight *component*
only where multiple entities need the same behaviour (companions reusing a
`CombatComponent`/`InventoryComponent`). Reuse the seams we have; don't rebuild.

**Why.** `game.gd` maintainability + companion/NPC reuse. **Complexity L (split) +
M (components). Deps:** FSM (exists).

## 4. Resource-driven data

**Where we are.** Content is JSON (`data/classes/races/spells/bestiary/…`) loaded
by `Rules`, plus GDScript consts (`EQUIP_SLOTS`, `PALETTES`, `WorldSkin.FAMILIES`,
forge `THEMES`). Already data-driven in spirit.

**Gap.** Not typed Godot `Resource` (.tres) assets, so the editor can't author
them and the AI-consumable schema is implicit. Some data lives in code consts.

**Evolve incrementally.** Introduce typed `Resource` classes where they pay —
designer-authored + AI-consumed content first (`ItemDef`, `ClassDef`, `NPCDef`,
`WorldThemeDef`). Migrate the highest-value tables (items, NPC defs, world
themes); leave stable tables as JSON with a documented schema. **Do not** convert
everything at once. **Complexity M–L (incremental). Deps:** none.

## 5. Asynchronous AI pipeline

**Where we are.** SSE streaming is non-blocking (the language gate buffers only
the opening). `Art` is a single-flight queue emitting `art_ready` — non-blocking.
The player is never frozen mid-scene.

**Gap.** Some turn-start latency: `Chronicle.recall(msg)` is `await`ed *before*
streaming. AI calls are ad-hoc `await Api.call_json` with no shared queue/worker
or cancellation. Forge generation is a blocking modal wait (with a spinner —
acceptable, but ad-hoc).

**Evolve → one async layer.** (a) Start the stream and the recall *concurrently*,
folding beats when ready (or prefetch). (b) A small `AiQueue` worker so every AI
call is one non-blocking path with callbacks, loading states, and cancel. (c)
Keep forge generation a clear loading state but never freeze input. The principle
is mostly met; this *formalises* it. **Complexity M. Deps:** Api, Composer,
Chronicle.

## 6. World Style Guide — the source of truth

**Where we are.** `WorldSkin` (families → palette/currency/art/materials/flavor/
music) + the world descriptor (lore/locations/cast/creatures) + now skin-driven
environment prompts (backlog #1). **This is an embryonic style guide** and the
keystone the other principles lean on.

**Gap.** It's partial — visual palette + art style + rooms — but lacks
typography, iconography, fashion, weapon/armor/creature style, lighting,
dialogue tone, lore tone, and per-asset **prompt templates** (portrait /
environment / item / creature / loading).

**Evolve `WorldSkin` → `WorldStyleGuide`.** The Campaign/World Forge produces a
structured guide stored on the world: `{palette, typography, iconography,
materials, tech_level, fashion, weapon_style, armor_style, creature_style,
lighting, music, lore_tone, dialogue_style, prompt_templates{…}}`. **Every**
downstream generator references it — Art prompts, portraits, item icons,
environment rooms, and `Composer`'s dialogue tone. The **deterministic-family
default stays the always-valid floor**; the LLM may refine, never gate. This is
the single most leverage-heavy evolution: it directly feeds §1, §2, §7, §9.

**Why.** One source of truth for all generated content and dialogue tone.
**Complexity L. Deps:** WorldSkin (exists), the Forges, Art, Composer.

## 7. Generative art pipeline — asset metadata

**Where we are.** `Art.ensure(key, prompt)` → `/generate` → `user://art/<key>.png`,
cached. **No metadata is stored** (prompt/seed/model/workflow/negative/params).

**Gap.** Can't regenerate deterministically or vary; no provenance; the cache
never evicts (TechnicalDebt/Backlog: unbounded disk growth, now worse with race
portraits + body dolls + lore art + per-skin rooms).

**Evolve → metadata sidecars + manifest.** Write `user://art/<key>.json` =
`{prompt, negative, seed, model, workflow, size, params, created, style_guide_ref}`
alongside each PNG; a manifest indexes all assets (enabling the **LRU eviction**
the backlog needs). The backend `/generate` returns seed/params (a small,
allowed backend evolution). **Complexity M (client) + S (backend). Deps:** Art,
backend `/generate` response, Style Guide (§6) for `prompt_templates`.

## 8. Engine modularity

**Where we are.** Autoloads separate concerns (Api=networking, Art=generation,
GameState/Combat/Rules=gameplay, Ui=rendering, Composer/Tags=AI, Chronicle=memory,
Mode=flow). Reasonable layering already.

**Gap.** `game.gd` cross-cuts UI+gameplay+AI+shop+forge (the main violation); a
few couplings reach across services (`Rules.attack_mod`→`GameState.inv`,
`Composer`→GameState/Chronicle/Rules). No explicit layer/dependency map.

**Evolve.** (a) Document the **layer map** (Engine · Gameplay · UI · AI ·
Persistence · Generation) and allowed dependency directions. (b) Split `game.gd`
(the concrete win, shared with §3). (c) Reduce cross-service reach via typed
context objects where it bites (the attack_mod/inv coupling). Keep the
singleton-service model — it's right for this project. **Complexity L (split) + S
(doc). Deps:** FSM.

## 9. AI quality — the Narrative Director

**Where we are.** `Composer.envelope` already assembles rich context: sheet
summary, clock/weather, inventory, spells, recalled beats, codex, quests, GM
tone directive, house rules, the protocol, and the language pin; combat feeds
per-round frames.

**Gap.** Context is assembled but not **verified** — no check that the minimum
exists before narrating; no explicit "nearby entities / current scene" object;
no internal "seed the missing fact" step when the GM references an unknown NPC.

**Evolve.** (a) A pre-turn **context completeness check** (sheet, place, recent
beats present; else seed a stub). (b) An explicit **scene state** (current
location, nearby codex NPCs, time/weather) as structured context. (c) The
Character Resources (§1) + Style Guide (§6) feed the Director structured, not
prose, context — richer and cheaper. "Request missing info internally" = a
pre-turn assembly pass, never a chatbot clarification to the player. **Complexity
M. Deps:** §1, §6, Composer.

---

## 10. Cross-cutting: what already satisfies the principles

- **Determinism boundary** (the brief's core invariant) is already enforced: the
  `[[tag]]` protocol is the only AI→state path; `game.gd._apply_world_tags` is the
  single chokepoint. Presentation tags (§2) extend this *without weakening it*.
- **Non-blocking play** is largely true today (SSE + Art queue). §5 formalises it.
- **Data-driven** is already the norm (JSON tables); §4 types it.
- **World theming** (M-B World Skin) is the seed of §6 — evolve, don't restart.

## 11. Evolution roadmap (milestones A0–A7)

Ordered by dependency and leverage. Each is shippable, preserves existing
behaviour, and ends with harnesses green.

| # | Milestone | Serves | Cx | Depends on |
|---|---|---|---|---|
| **A0** | Layer map doc + **game.gd split** into FSM view scenes | §3 §8 | L | FSM (done) |
| **A1** | **WorldStyleGuide** (evolve WorldSkin: typography/iconography/materials/fashion/dialogue-tone/prompt-templates; deterministic floor, LLM-refined) | §6 (feeds 1/2/7/9) | L | WorldSkin, Forges |
| **A2** | **Art metadata sidecars + manifest + LRU** (+ backend returns seed/params) | §7 | M | Art, backend |
| **A3** | **Presentation tags** (mood/portrait/ambient/music/camera → presentation systems only) | §2 | M | Tags, Sfx, A1 |
| **A4** | **CharacterResource + relationship/reputation graph** (extractor-fed) | §1 | L | Chronicle, Composer, A1 |
| **A5** | **AiQueue async layer** (concurrent recall+stream, callbacks, cancel, loading states) | §5 | M | Api, Composer |
| **A6** | **Director context verification + scene state** | §9 | M | A1, A4 |
| **A7** | **Typed Resource migration** (items/classes/NPC/world-theme first) | §4 | M–L | — (incremental, ongoing) |

**Sequencing rationale.** A0 gives clean seams so everything after is tractable.
A1 is the keystone source-of-truth the most principles consume, and it's a direct
evolution of the shipped World Skin. A2 is cheap and unblocks the cache debt +
regeneration. A3 is high player-facing value and a pure tag extension. A4/A6 make
the Director genuinely context-aware. A5 formalises the async guarantee. A7 runs
in the background throughout.

## 12. Preservation guarantees (per the brief)

- No milestone changes the Godot/FastAPI split or the `[[tag]]` determinism rule.
- Every item **evolves** a working system: WorldSkin→StyleGuide, tags→+presentation
  tags, JSON→typed resources *incrementally*, game.gd→split views, Art→+metadata.
- Deterministic gameplay stays entirely in Godot; the AI only ever *suggests*
  (narration + presentation tags) and *requests* state via `[[tag]]`, which
  deterministic systems validate and apply.
