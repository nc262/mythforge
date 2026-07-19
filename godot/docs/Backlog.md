# Backlog — the full deep dive (2026-07-18)

One consolidated view of everything outstanding, pulled from FeatureMatrix,
Roadmap, TechnicalDebt, KnownIssues, FutureIdeas, and this session's sprint.
Priority **P1** (core play) → **P4** (nice-to-have). Effort **S/M/L/XL**.

> **Reconciliation note.** The First-Complete-Experience sprint (language guard,
> World Skin, Lore Book, skill-tree motif, Chronicles gallery, paper doll, AAA
> sheet, menu legibility) is **not yet in FeatureMatrix/Roadmap** — those trackers
> predate it. §1 lists what this session resolved so the matrix can be updated;
> §2–§5 are the true remaining backlog.

---

## 1. Resolved this session (matrix/roadmap need these rows)

| Item | Was tracked as | Now |
|---|---|---|
| Language integrity guard | (not tracked) | ✅ M-A: pin + drift detect + silent retry |
| Per-world theming beyond 3 built-ins | "per-world theming ✅" (only 3) | ✅ M-B World Skin: 8 families, palette/currency/art/music/materials |
| MythButton engraving contrast | "steel-plate engraving contrast pass 🔲" | ✅ M-E: raised outlined lettering |
| Emoji-free sweep (controls) | "full in-game emoji-free sweep 🔲" | ✅ **COMPLETE (2026-07-18)** — bake pipeline (`Ui.ico`/`[img]` inline + `.icon` on controls); every displayed emoji across game.gd, all 4 forges, windows, autoloads gone. Functional icons → drawn art; garnish → clean text (BG3 rule). Zero glyphs render. |
| Illustrated Lore Book | (not tracked) | ✅ M-C: aggregated encyclopedia + `[[lore]]` growth |
| Chronicles as cover gallery + Continue fold | "Continue → save picker ✅" (plain) | ✅ M-E: illustrated covers, open-book-from-Hall |
| World-adaptive skill tree | "constellation ✅" (single motif) | ✅ M-D: circuit/gears/chart/constellation motifs |
| AAA character sheet | "Hero's Record ✅" (fold list) | ✅ tabbed Record/Gear/Skills/Powers/Story |
| Paper doll + equipment breadth | "3D turntable 🔲", "paper doll (FutureIdeas)" | ✅ M-F Stage A: full-body doll + 13 slots |
| Forge-time portrait preview | "forge-time preview 🔲" | ✅ live Envision in the Appearance stage |
| Race art in hero forge | (not tracked) | ✅ per-race portraits in Heritage |
| Real-UI playthrough test harness | (not tracked) | ✅ `tests/ui_playthrough` drives loot→equip→damage/heal→combat→levelup→persistence through the real game scene; caught 2 shipped crashes |
| `THE END` completion never fired | (not tracked) | ✅ regex bug — `"\b"` was a backspace char; fixed + auto-snapshot + Chronicles complete badge |
| Save-DC spells / class-feature actions / companion kits / B1 / B2 / write-queue | see §2–4 | ✅ all resolved 2026-07-18 (rows struck through below) |

---

## 2. Bugs & correctness (from KnownIssues, re-triaged)

| # | Issue | Pri | Effort | Note |
|---|---|---|---|---|
| B1 | ~~`_show_saves`/Chronicles fetches each save's state **serially**~~ | ~~P2~~ | ✅ | **DONE 2026-07-18** — cards build sync; each state fetch fires concurrently, fills its caption when it lands. |
| B2 | ~~Art cache **never evicts** (no LRU)~~ | ~~P2~~ | ✅ | **DONE** (A2) — 700 MB budget, manifest + LRU `_enforce_budget`/`_evict`. |
| B3 | `Rules.attack_mod` couples to `GameState.inv()` when inv omitted | P3 | S | Latent wrong-bonus footgun; typed context object in the game.gd split. |
| B4 | Combat attack rolls don't play the dice-moment overlay | P3 | M | Tracker rolls are internal — less drama. |
| B5 | Multiple missing world key-arts generate **sequentially** on menu load, lagging chat image requests | P3 | M | Art queue priority lanes. |
| B6 | Backend auth = single shared cookie file per OS user | P4 | — | Fine solo; matters at multiplayer. |
| B7 | Godot 4.7 shutdown RID/StringName leak noise (headless) | P4 | — | Upstream; grep-filtered. |

## 3. Technical debt (re-triaged; two got worse this session)

| Debt | Pri | Effort | Note |
|---|---|---|---|
| **game.gd god-script** (~1.4k+ lines; grew again with the language guard, lore, paper-doll wiring) | **P2** | L | Split chat_view / panels / dialogs as child scenes under the FSM. The single biggest structural risk. |
| **ForgeFlow base extraction** — now **four** forges (character/campaign/world/adventure) duplicate the ~60-line rail/title/nav scaffold | **P2** | M | The "extract when a 3rd appears" trigger is well past; a shared base would cut real duplication. |
| **Per-world EAS room variants** — `Art.ENV_PROMPTS` are fantasy-flavored ("mythic forge", "war room"); a cyberpunk campaign gets a cyber *palette* but a fantasy *room* | **P2** | M | Exposed by M-B. Skin should drive env prompts too (a "skin slice 3"). |
| ~~State writes are fire-and-forget PUTs, no debounce/retry~~ | ~~P2~~ | ✅ | **DONE** (A5) — `save_kind` updates local instantly + enqueues; `_drain_writes` coalesces (last-write-wins) + retries. |
| ~~Per-world EAS room variants (fantasy-flavored ENV_PROMPTS)~~ | ~~P2~~ | ✅ | **DONE** (A1) — `ENV_ROLE` + `env_resolved`/`env_prompt` drive per-world rooms from the skin. |
| Companion kit generic (Fighter/AC13) | ~~P3~~ | ✅ | **DONE 2026-07-18** — `infer_companion_kit` maps role→class/AC/HP. |
| Enemy stats by name-regex tiers vs bestiary stat blocks | P3 | M | Flavorless foes; derive from bestiary + world. |
| Companion kit generic (Fighter/AC13) | P3 | S | Class inference from codex role. |
| world_map carries its own pan/zoom (pre-MythCamera) | P3 | S | Adopt MythCamera next time it's touched. |
| Envelope rebuilt as strings each turn | P3 | M | Context budgeter when sections grow. |
| Tests hit the live backend | P3 | M | Mock SSE fixture for a CI lane. |
| Terrain sampler is a colour heuristic | P3 | M | LLM-authored terrain layout per battle map. |

## 4. Feature gaps (from FeatureMatrix 🔲/🟡, still open)

**Play systems**
- ~~Save-DC spells~~ — ✅ **DONE 2026-07-18**: foe rolls a save vs your spell DC (tier-derived save mod); for-half/negate; typed vuln/resist.
- ~~More class-feature actions: Bardic Inspiration, Lay on Hands, Wild Shape~~ — ✅ **DONE 2026-07-18** (+ Channel Divinity).
- Token **drag** on the battle grid (click-move shipped) — P3 / S
- LLM-authored terrain layout — P3 / M
- ASI split (+1/+1 vs +2) — P3 / S
- Multiclassing — P4 / L
- Recipe-based crafting v2 (typed components from drops) — P4 / M

**Shell & creation**
- **GM Forge** (custom GM personas) — P3 / M
- **Persona/Companion Forge** (create-your-own companions: portrait/suggest/describe) — P3 / L
- Companion chat: seed photos, clear-chat — P3 / S
- Campaigns tab (cross-world premises) — P4 / M
- Staggered card-entrance animation — P4 / S

**Presentation**
- **Controller support** — **P2 / L** (flagged in the matrix as a *target-game requirement*; needs the FSM input-map-per-state pass)
- Combat music system (only tint+sting today) — P3 / M
- Raw dice tray (manual d4–d20 + mod) — P3 / S
- Minimap overlay — P3 / M
- x/y world-map render + auto here-tracking from prose — P3 / L
- Complete-badge on finished saves + auto-snapshot on THE END — P3 / S
- Recap art; scene-reactive ambient layers — P3 / M

**EAS (M8 next waves)**
- Generated prop/frame/banner assets — P2 / L
- Title-screen environment painting — P2 / M
- Dialogue fireside with NPC portrait staging — P2 / M
- (Per-world room variants folded into §3 above)

**AI & voice**
- **TTS narration** — ⛔ BLOCKED on a server-side voice provider (probe 503); client wiring is ready
- STT push-to-talk — P4 / M
- Inline message edit (↻ retell shipped) — P3 / M
- Model routing (big model for scene-setting, small for quick turns) — P3 / M
- Vision loop (feed scene art through /describe so the GM sees the picture) — P4 / M
- Structured per-NPC voices in the envelope — P3 / S

## 5. This-sprint carry-overs (deliberately deferred)

| Item | State | Unlock |
|---|---|---|
| **M-F Stage C — true 3D character** | Paused by Director | An asset-sourcing decision (commissioned vs. generated-3D vs. bought pack). See CharacterRender.md. |
| Narration bbcode emoji (💰🎒📖 in `_say_system`) | ✅ **DONE (2026-07-18)** — `_say_system(text, glyph)` leads with a live MythIcon; RichText uses `Ui.ico`. Zero glyphs. | — |
| World Skin palette from the LLM | Deterministic families only | Worldsmith emits palette hexes → merge → contrast-clamp (the guard is already in place). |
| **Material textures on surfaces (stone / leather / parchment / glass)** — *user request 2026-07-18* | Panels/cards/dialogs use flat skin fills; `WorldSkin.material_sb` already has glass/neon/copper/carbon generators | **P2 / M.** Apply real per-world material textures (stone for norse/fantasy, leather for pirate, parchment for the book, brushed glass for cyber/space) to panel/card/dialog backgrounds. Extend `material_sb` + wire into the shared panel styleboxes. |

## 6. FutureIdeas parking lot (uncommitted)

Relationship/reputation web · engine-verified quest objectives · world-sim depth
(NPC goals, seasons, festivals) · camp mode with banter · animated 3D dice ·
cinematic finale slideshow + stats · photo/share mode · Steam achievements &
Workshop · co-op party + WebRTC voice · one-click bundled backend installer.

---

## 7. Recommended next (if the sprint continues)

Ranked by **impact ÷ effort**, favouring things this session made urgent or exposed:

1. **Per-world EAS room variants** (§3) — M. The World Skin themes colours but the
   *rooms* are still fantasy; a cyber campaign in a fantasy forge is the most
   visible remaining inconsistency. Skin should drive `ENV_PROMPTS`.
2. **Art-cache LRU + parallel save fetch** (B2 + B1) — M together. We generate a lot
   more art now, and the Chronicles gallery made serial fetches felt.
3. **ForgeFlow base extraction** (§3) — M. Four forges of duplicated scaffold; pays
   down real debt and de-risks the next forge.
4. **Save-DC spells** (§4) — M. The biggest *mechanical* gap in combat (only damage
   spells resolve); casters feel half-implemented without it.
5. **game.gd split** (§3) — L. The structural keystone for everything after; best done
   deliberately, not under feature pressure.
6. **Controller support** (§4) — L. The one P2 platform requirement still open.

Everything else is genuine P3/P4 polish or is blocked (TTS) / paused (3D) / parked
(FutureIdeas).

## 8. Doc hygiene (should follow this audit)

- Add matrix rows for the §1 sprint work (the matrix's own rule: no feature ships
  un-tracked). New docs already exist: `Sprint-FirstImpression.md`, `WorldSkin.md`,
  `CharacterRender.md`.
- Retire the resolved 🔲 markers in FeatureMatrix (engraving contrast, forge-time
  preview, per-world theming scope).
- Add a Roadmap **M10 — First Complete Experience** milestone summarising M-A…M-F.
