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
| B3 | ~~`Rules.attack_mod` couples to `GameState.inv()`~~ | ✅ | — | Verified stale 2026-07-21 — inv is an explicit param, no GameState fallback. |
| B4 | ~~Combat attack rolls don't play the dice-moment overlay~~ | ✅ | — | ✅ **DONE 2026-07-21** — player_attack returns roll+caption; the swing animates. |
| B5 | ~~Art queue priority lanes~~ | ✅ | — | ✅ **DONE 2026-07-21** — ensure(front=true): battle maps + hero portraits jump menu backfill. |
| B6 | Backend auth = single shared cookie file per OS user | P4 | — | Fine solo; matters at multiplayer. |
| B7 | Godot 4.7 shutdown RID/StringName leak noise (headless) | P4 | — | Upstream; grep-filtered. |

## 3. Technical debt (re-triaged; two got worse this session)

| Debt | Pri | Effort | Note |
|---|---|---|---|
| ~~**game.gd god-script**~~ | ~~P2~~ | ✅ | **DONE 2026-07-18** — A0 split complete: merchant/GM-tuner/level-up/reaction extracted to windows; journal/chronicle/atlas folded into lore_book/world_map. 2461→~2000 lines; what remains is the streaming/tag/combat core. |
| ~~**ForgeFlow base extraction**~~ | ~~P2~~ | ✅ | **DONE 2026-07-18** — ui/forge_flow.gd; all four forges are stage-content only; GM + Companion forges built on it same-day. |
| ~~**Per-world EAS room variants**~~ | ✅ | — | Duplicate row — already done as A1 (`ENV_ROLE` + `env_resolved`), see row below. |
| ~~State writes are fire-and-forget PUTs, no debounce/retry~~ | ~~P2~~ | ✅ | **DONE** (A5) — `save_kind` updates local instantly + enqueues; `_drain_writes` coalesces (last-write-wins) + retries. |
| ~~Per-world EAS room variants (fantasy-flavored ENV_PROMPTS)~~ | ~~P2~~ | ✅ | **DONE** (A1) — `ENV_ROLE` + `env_resolved`/`env_prompt` drive per-world rooms from the skin. |
| Companion kit generic (Fighter/AC13) | ~~P3~~ | ✅ | **DONE 2026-07-18** — `infer_companion_kit` maps role→class/AC/HP. |
| ~~Enemy stats by name-regex tiers~~ | ✅ | — | ✅ **DONE 2026-07-21** — bestiary tier → HP band/AC/atk/dmg dice; regex stays as fallback. |
| ~~Companion kit generic~~ | ✅ | — | Duplicate row — done 2026-07-18 (`infer_companion_kit`). |
| ~~world_map own pan/zoom~~ | ✅ | — | ✅ **DONE 2026-07-21** — MythCamera adopted, hand-rolled camera deleted. |
| ~~Envelope context budgeter~~ | ✅ | — | ✅ **DONE 2026-07-21** — per-section 1400-char word-boundary cap, marked trims. |
| ~~Tests hit the live backend~~ | ✅ | — | Stale — ui_playthrough + click_driver run on Api.test_mode (canned SSE); legacy tests/playthrough.gd is the only live-backend one and is superseded. |
| ~~Terrain sampler colour heuristic~~ | ✅ | — | ✅ **DONE 2026-07-21** — [[terrain]] tag lets the GM lay block/water/cover; heuristic bake stays as fallback. |

## 4. Feature gaps (from FeatureMatrix 🔲/🟡, still open)

**Play systems**
- ~~Save-DC spells~~ — ✅ **DONE 2026-07-18**: foe rolls a save vs your spell DC (tier-derived save mod); for-half/negate; typed vuln/resist.
- ~~More class-feature actions: Bardic Inspiration, Lay on Hands, Wild Shape~~ — ✅ **DONE 2026-07-18** (+ Channel Divinity).
- ~~Token **drag** on the battle grid~~ — ✅ DONE 2026-07-21 (lift, ghost, drop-to-move)
- ~~LLM-authored terrain layout~~ — ✅ DONE 2026-07-21 ([[terrain]] tag)
- ~~ASI split (+1/+1 vs +2)~~ — ✅ DONE 2026-07-21 (all 15 pairs in the ceremony)
- ~~Multiclassing~~ — ✅ **DONE 2026-07-18**: classes[] on the sheet, ceremony redirect, combined caster level, prereqs.
- ~~Recipe-based crafting v2~~ — ✅ DONE 2026-07-21 (recipes table, component consumption, dice-menu craft lane, GM seeds components via loot)

**Shell & creation**
- ~~**GM Forge**~~ — ✅ **DONE 2026-07-18**: full pillar; seals to _global.cgms; Campaign Forge Voice stage offers forged personas.
- ~~**Persona/Companion Forge**~~ — ✅ **DONE 2026-07-18**: full pillar; npc-<slug> portrait shared with journal/codex; Party stage picks ride in on day one.
- ~~Companion chat: seed photos, clear-chat~~ — ✅ DONE 2026-07-21 (fireside staging + priority portrait + Clear-the-table)
- ~~Campaigns tab~~ — ✅ DONE 2026-07-21 (CAMPAIGNS shelf in the Hall)
- ~~Staggered card-entrance animation~~ — ✅ DONE 2026-07-21 (worlds grid + campaign shelf)

**Presentation**
- ~~**Controller support**~~ — ✅ **DONE 2026-07-18**: Pad autoload (runtime InputMap), universal focus seeding, grid pad cursor, mf_roll/mf_end_turn. Ceilings: stage rail + combat spell links stay mouse-only.
- ~~Combat music system~~ — ✅ verified already shipped (combat drone crossfade + [[music cue]])
- ~~Raw dice tray~~ — ✅ DONE 2026-07-21 (d4–d100 + expression roller in the dice menu)
- ~~Minimap overlay~~ — ✅ DONE 2026-07-21 (corner chart, lamp-dots, you-are-here, click → Atlas)
- ~~x/y world-map render + auto here-tracking~~ — ✅ DONE 2026-07-21 (x/y chart shipped earlier; [[scene]] prose now moves the pin)
- ~~Complete-badge + auto-snapshot on THE END~~ — ✅ shipped with the THE END regex fix (2026-07-18)
- ~~Recap art~~ — ✅ DONE 2026-07-21 (world seal on the recap card); scene-reactive ambient layers covered by [[mood]]/[[music]] presentation tags

**EAS (M8 next waves)**
- ~~Generated prop/frame/banner assets~~ — ✅ first slice DONE 2026-07-21 (heraldic title banner; MythPlate is the shared frame); more props land as screens call for them
- ~~Title-screen environment painting~~ — ✅ DONE 2026-07-21 (env-hall behind the title)
- ~~Dialogue fireside with NPC portrait staging~~ — ✅ DONE 2026-07-21 (fireside room + breathing portrait at the table)
- (Per-world room variants folded into §3 above)

**AI & voice**
- **TTS narration** — ⛔ BLOCKED on a server-side voice provider (probe 503); client wiring is ready
- ~~STT push-to-talk~~ — ✅ DONE 2026-07-21 (hold-the-quill record → /api/stt/transcribe → input box; server 503s politely without a provider)
- ~~Inline message edit~~ — ✅ DONE 2026-07-21 (Ctrl+E rewords your last line, stale exchange leaves the thread)
- Model routing — ⛔ BLOCKED: backend model is per-session (chat_stream has no per-message override); needs a backend field before any client work
- Vision loop — ⛔ BLOCKED: /describe is an appearance-anchor endpoint (upload-based); a scene-describe route is a backend task
- ~~Structured per-NPC voices~~ — ✅ DONE 2026-07-21 ([[npc voice=]] → cast canon, dialogue kept in voice)

## 5. This-sprint carry-overs (deliberately deferred)

| Item | State | Unlock |
|---|---|---|
| **M-F Stage C — true 3D character** | Paused by Director | An asset-sourcing decision (commissioned vs. generated-3D vs. bought pack). See CharacterRender.md. |
| Narration bbcode emoji (💰🎒📖 in `_say_system`) | ✅ **DONE (2026-07-18)** — `_say_system(text, glyph)` leads with a live MythIcon; RichText uses `Ui.ico`. Zero glyphs. | — |
| World Skin palette from the LLM | Deterministic families only | Worldsmith emits palette hexes → merge → contrast-clamp (the guard is already in place). |
| ~~**Material textures on surfaces**~~ | ✅ **DONE 2026-07-21** — `stone_tex`/`parchment_tex` generators + per-family `panel`/`page` material roles; menu hero panel + Lore Book pages wear them (stone in fantasy-kin, glass on cyber/space, leather in Everyday). Extend to more surfaces as screenshots direct. | — |
| ~~**World-skinned vendor stock**~~ | ✅ **DONE 2026-07-21** — `vendor_stock_cyber/everyday/space` in tables.json (names carry mk_item classifier keywords so stats resolve); `Rules.vendor_stock()` picks by family, others fall back to the fantasy base. | — |
| ~~**Real-UI click-driver playtest tool**~~ | ✅ **DONE 2026-07-21** — `tests/click_driver.tscn`: real synthesized mouse events through the input pipeline (embedder-routed into dialog windows), per-station occlusion/off-screen audit, outcome-asserted click paths (menu, 9 tabs, shop, book), PNGs per station in windowed runs, `MF_LIVE=1` for the live stack. **First run caught 2 shipped bugs**: tab rail overflowed the window (Chronicle/The Table unreachable) and the menu wrapped taller than the screen (OK button off-screen). | — |

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
