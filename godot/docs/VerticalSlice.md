# Vertical Slice Audit — Mythforge

**Milestone declared 2026-07-21.** The objective is no longer feature count.
The objective is that a stranger's first thirty minutes feel indistinguishable
from a professionally produced RPG.

**Standing rule from this point:** *a feature is not finished because it works.*
Every visible screen must reach AAA presentation quality to be called complete.

**Sprint order, every sprint:** Audit → Experience Design → UX Review → Visual
Design → Architecture Review → Implementation → Playtesting → Polish →
Documentation → Commit.

---

## 0. Executive summary

Mythforge is **mechanically deep and visually inconsistent**. The engine, the
tag protocol, the world-skin system, and the documentation are genuinely
strong — better than most indie RPGs. What betrays it is **the seams**: the
moments *between* screens, the silence where feedback should be, and the raw
engineering that leaks through when something goes wrong.

**Overall vertical-slice readiness: ~65%.**

The three findings that most damage perceived quality, in order:

1. **The game never transitions — it cuts.** Six `change_scene_to_file` calls
   with no fade, no wipe, no hold. Launch→menu, menu→play, play→menu are all
   hard cuts. Nothing in commercial games cuts like this; it is the single
   loudest "prototype" signal in the build.
2. **The game is nearly silent.** Four sound effects exist (`chime`, `dice`,
   `hit`, `sting`) across 29 call sites. **No button anywhere makes a sound.**
   No hover, no click, no page turn, no equip, no level-up fanfare, no travel.
   Ambient beds carry the whole audio identity alone.
3. **There is no loading experience.** The FSM declares a `Loading` state that
   *nothing renders*. Pressing Play swaps the scene instantly, then the player
   watches hydration, portraits and room art pop in over several seconds.

Two related failures of first impression:

- **The very first screen can show `Login failed (0)`** — a raw HTTP status, to
  a player whose only sin was launching before the backend was up.
- **Tooltips essentially don't exist**: six `tooltip_text` assignments in the
  entire game. A 12-button action bar explains nothing on hover.

---

## 1. System-by-system audit

Scores are 0–100 where **100 = shippable in a commercial release**, not
"implemented." V/UX/T/A = Visual, UX, Technical, Architecture quality.

### Summary matrix

| System | Maturity | V | UX | T | A | Headline gap |
|---|---|---|---|---|---|---|
| Main Menu | 70% | B | B | A | A | hard cuts, no hover audio, ↻/▶ glyphs |
| Character Forge | 75% | B+ | B+ | A | A | no stage transitions, no audio |
| Campaign Forge | 70% | B | B | A | A | long text stages, thin feedback |
| Adventure Forge | 70% | B | B | A | A | orchestration invisible to player |
| Inventory (Gear tab) | 75% | B+ | B | A | A | no drag-to-equip since merge |
| Character Sheet (THE MENU) | 75% | B+ | A- | A | A | 9 tabs unequal in polish |
| Dialogue | 55% | C+ | C+ | B+ | B+ | no dialogue UI — it's chat bubbles |
| Combat | 70% | B | C+ | A | A | readability untested, log-heavy |
| Merchant | 70% | B | B | A | A | list widgets, not a shop |
| Quest Journal | 40% | C | C | B | B | a Lore Book tab, no objective tracking |
| Lore Book | 70% | B | B | A | A | dense pages, no reading rhythm |
| Map | 70% | B+ | B | A | A | pin labels collide at zoom |
| Minimap | 60% | B | B | A | A | unplayed; no fog reveal beat |
| Travel | 55% | C+ | C+ | A | A | instant; no journey moment |
| Save / Load | 60% | C | C+ | A- | A | invisible autosave, no confirmation |
| Chronicles | 65% | B | B | A | A | covers uneven; no completion ceremony |
| UI (MDL) | 70% | B+ | B | A | A | 6 tooltips total; 24 glyph leaks |
| Animations | 55% | B | B | A | B | **no scene transitions at all** |
| Audio | 30% | — | D | B | B | **no UI feedback layer** |
| Visual Effects | 60% | B | B | A | A | combat-only; menus have none |
| World Theming | 80% | A- | A- | A | A | materials on 2 surfaces; stock 3/8 |
| Performance | 60% | — | — | B | B | never profiled; 8 per-frame loops |
| Accessibility | 25% | — | D | B | B | reduce-motion only |
| Controller | 60% | — | C+ | B+ | A | forge rail + spell links mouse-only |
| LLM Integration | 80% | — | B+ | A | A | first-token wait unmasked |
| ComfyUI Integration | 75% | B+ | C+ | A | A | art pops in; no placeholder craft |
| Documentation | 85% | — | — | A | A | matrix rows lag the code |
| Testing | 70% | — | — | A | A | click-driver covers 4 of ~12 screens |

---

### MAIN MENU — 70%

- **Visual** B — painted hall (`env-hall`), heraldic banner, material plates, cinematic boot. Genuinely handsome.
- **UX** B — 11 primary plates in one column is a long list; no hover sound; the eye has no clear "start here."
- **Technical/Architecture** A — 997 lines but cleanly sectioned; MythButton library carries the look.
- **Missing:** hover/click audio · scene transition on every exit · tooltips on plates.
- **Bugs:** `⬆` renders on the Import-world card (MDL violation); `↻`/`▶` glyphs at 5+ sites in save cards.
- **Polish:** stagger the plate entrance (exists for worlds grid, not the title column) · banner isn't world-skinned (always crimson) · CONTINUE deserves visual primacy over the ten forges.
- **Debt:** `_show_*` view functions rebuild `_content` wholesale each time — cheap now, fragile later.
- **Depends on:** transition system, audio layer.
- **Effort:** M.

### CHARACTER FORGE — 75%

- **Visual** B+ — race portraits, live Envision preview, ForgeFlow rail. The best-looking screen in the game.
- **UX** B+ — stage rail communicates progress; but stage-to-stage is an instant content swap with no motion.
- **Technical/Architecture** A — 589 lines on the shared ForgeFlow base.
- **Missing:** stage transitions · audio on commit · the final "your hero is forged" beat is a `_say_system` line, not a ceremony.
- **Polish:** portrait generation wait is unmasked (a blank frame until ComfyUI answers) · ability-array assignment lacks tactile feedback.
- **Effort:** M.

### CAMPAIGN FORGE — 70%

- 660 lines, six stages, progress-lit map backdrop (a nice touch). Same transition/audio gaps.
- **UX** B — several stages are long-form text entry; no character counters, no examples inline.
- **Polish:** the map backdrop brightening with progress is the strongest idea here and deserves amplification.
- **Effort:** M.

### ADVENTURE FORGE — 70%

- Orchestrates hero→campaign→party→difficulty→rules→preview. Architecturally the cleanest flow.
- **UX** B — the player doesn't feel the orchestration; it reads as another form sequence.
- **Missing:** a preview beat that *sells* the adventure before "begin" (art + premise + party portrait in one composed frame).
- **Effort:** M.

### INVENTORY (Gear tab) — 75%

- **Visual** B+ — painted item art, rarity halos, capacity strap, paper-doll sockets, MythPlate inspect.
- **UX** B — **drag-to-equip was lost in the merge**; the retired flat-lay window had it, the Gear tab does not. Double-click and right-click only.
- **Missing:** drag-and-drop · sort/filter · comparison on hover against the worn piece in the *socket* (tooltips have it, sockets don't).
- **Effort:** M.

### CHARACTER SHEET / THE MENU — 75%

- **Visual** B+ · **UX** A- — the tabbed menu is the right structure and reads as a real game menu.
- **Gap:** the nine tabs are unequal — Record and Gear are polished; Skills and Powers are plain lists; The Table is a settings dump.
- **Missing:** tab transition (instant visibility swap) · no keyboard tab cycling (Q/E or bumpers).
- **Effort:** M.

### DIALOGUE — 55%

- **The weakest major system.** There is no dialogue UI: NPC speech arrives as GM prose inside chat bubbles. The fireside staging (portrait + room) exists only in *companion chat*, not in play.
- **Missing:** in-play speaker attribution · portrait staging when an NPC speaks · dialogue choice affordances (currently free-text only) · voice/tone cue surfaced from `[[npc voice=]]`.
- **Effort:** L. *This is the largest single perceived-quality gap after the seams.*

### COMBAT — 70%

- **Technical** A — grid, terrain, reactions, tiers, cover, opportunity, drag-to-move, dice moments. Genuinely deep.
- **UX** C+ — the fight reads as a *log*. Damage numbers rise on the board (good) but initiative, budget, and consequences live in text panels.
- **Missing:** turn-start banner · clear "your turn" state change · target highlight before commit · victory/defeat ceremony (currently a line of text).
- **Bugs:** attack rolls animate now, but enemy turns still resolve silently in bulk during End Turn.
- **Effort:** L.

### MERCHANT — 70%

- Painted item icons, buy-primary hierarchy, ghost haggle, detail strip. Solid pass done.
- **UX** B — two `ItemList` widgets are still *engine widgets*, not a shop counter.
- **Missing:** purchase confirmation beat · coin sound · stock refresh over time.
- **Effort:** M.

### QUEST JOURNAL — 40%

- **The least developed system.** Quests exist as data (`[[quest]]`, `quests_text()`) and render as a Lore Book tab list.
- **Missing:** objective tracking (no steps/completion state) · active-quest HUD marker · quest-complete beat · map linkage (the Atlas doesn't show quest destinations except via text matching).
- **Effort:** L.

### LORE BOOK — 70%

- World-skinned kind chips, tab scrim, scroll fade, material pages. Good bones.
- **UX** B — every category is the same card-list rhythm; a 40-entry Bestiary reads identically to a 3-entry Campaigns tab.
- **Missing:** search/filter · entry detail view (everything is a summary row).
- **Effort:** M.

### MAP — 70%

- Camera, fog, lamp pins, hover roads, quest pulse, in-panel header. Strong.
- **Gap:** labels collide when places cluster; no legend; travel confirmation is immediate on click.
- **Effort:** S–M.

### MINIMAP — 60%

- Just built, never played. Corner chart, lamp-dots, breathing you-are-here, click→Atlas.
- **Risk:** untested against real charts — pin density and legibility at 190×124 unknown.
- **Missing:** fog-reveal beat when a new place is discovered.
- **Effort:** S.

### TRAVEL — 55%

- Mechanically complete (time advance, 1-in-5 encounter, fog burn, scene repaint).
- **UX** C+ — travel is instant. No journey moment, no map animation, no "days pass" beat. The strongest missed *cinematic* opportunity in the game.
- **Effort:** M.

### SAVE / LOAD — 60%

- **Technical** A- — debounced write queue, coalescing, retry, snapshots, resume.
- **UX** C+ — **the player never sees it happen.** No save indicator, no confirmation, no "last saved" line. Trust in a save system is built by *showing* it.
- **Missing:** autosave indicator · explicit save feedback · load-failure copy in human language.
- **Effort:** S.

### CHRONICLES — 65%

- Illustrated covers, open-from-Hall, resume-from-chapter.
- **Missing:** completion ceremony when a tale reaches THE END (badge exists; the *moment* doesn't) · cover art quality varies wildly.
- **Effort:** M.

### UI / MDL — 70%

- 16 components, procedural materials, world-skinned palettes, focus rings, drawn icon library. The design *system* is real and better than most indies.
- **Bugs:** **24 sites still render raw glyphs** in UI strings — including `⏳`/`✅`/`✕` inside `myth_forge_step.gd`, a *shared* component, i.e. the MDL law is violated in the library itself.
- **Missing:** **tooltips (6 in the entire game)** · no disabled-state vocabulary · no toast/notification pattern.
- **Effort:** M.

### ANIMATIONS — 55%

- **Vocabulary** is good: `polish` (hover lift/press dip), `reveal`, `reveal_children` (stagger), `breathe`, `pulse`, `ritual_open`, `rise_text` — all reduce-motion aware.
- **The hole:** **no scene transitions.** Also no page/tab transitions, no travel motion, no combat turn motion.
- **Effort:** M for transitions; S each for the rest.

### AUDIO — 30% ⚠️ lowest score in the build

- Four effects total (`chime`, `dice`, `hit`, `sting`), five ambient beds, crossfade system, settings toggles.
- **No UI feedback whatsoever**: no hover, click, open, close, page, equip, purchase, level-up, quest-complete, travel, error.
- All existing sounds are synthesized via `scripts/make_sfx.py` — **the pipeline to add more already exists**, which makes this a cheap, enormous win.
- **Effort:** M (synthesis + wiring).

### VISUAL EFFECTS — 60%

- Combat has impact blooms, lunges, board shudder, rising damage. Menus and forges have essentially none.
- **Missing:** level-up burst · loot shimmer · quest-complete flourish · transition effects.
- **Effort:** M.

### WORLD THEMING — 80% (strongest system)

- 8 families driving palette, currency, art style, music, materials, place vocabulary, class reskins, environment prompts.
- **Gaps:** materials wear on **2 surfaces only** (menu hero panel, Lore Book pages) · vendor stock covers **3 of 8 families** · the title banner isn't skinned.
- **Effort:** M to finish the sweep.

### PERFORMANCE — 60% (unmeasured)

- Eight `_process` loops calling `queue_redraw()` every frame (environment motes, map, grid, minimap, skill tree, backdrop, cinematic, forge flow). Several run simultaneously.
- Art cache has a 700 MB LRU budget; textures cached in memory dictionaries with no eviction.
- **Never profiled. No frame budget, no target, no measurement.** Score reflects ignorance, not known badness.
- **Effort:** S to measure; unknown to fix.

### ACCESSIBILITY — 25%

- `reduce_motion` exists and is honored in 17 files — genuinely good, and rare.
- **Everything else absent:** no text scaling, no colorblind-safe palette check, no high-contrast mode, no key rebinding UI, no font choice, no narration speed control.
- Contrast was bumped one step this sprint but never *measured* against WCAG.
- **Effort:** M.

### CONTROLLER — 60%

- `Pad` autoload: runtime InputMap, focus seeding, grid cursor, `mf_roll`/`mf_end_turn`/`mf_menu`.
- **Ceilings:** forge stage rail and combat spell links are mouse-only; no menu tab cycling on bumpers; no button-prompt glyphs anywhere in the UI.
- **Effort:** M.

### LLM INTEGRATION — 80%

- Tag protocol, language guard with silent retry, context envelope with budgeter, per-NPC voices, GM tone knobs, world style guide. Architecturally excellent.
- **UX gap:** the **first-token wait is unmasked** on a local model — the player stares at a static screen with no "the GM is thinking" state.
- **Blocked:** model routing (backend has no per-message override).
- **Effort:** S for the thinking state.

### COMFYUI INTEGRATION — 75%

- Single-flight queue with priority lane, LRU manifest, per-asset sidecars, world-skinned prompts.
- **UX gap:** art **pops in**. No placeholder craft (a painted "not yet" frame), no fade-in on arrival for most surfaces, no progress signal.
- **Effort:** M.

### DOCUMENTATION — 85% (strongest non-code area)

- 30+ docs including per-ritual specs, design system, world skin, build procedure, backlog.
- **Gap:** FeatureMatrix and Roadmap rows lag the code by two sprints (Backlog §8 never executed).
- **Effort:** S.

### TESTING — 70%

- Two real harnesses: `ui_playthrough` (mechanics through the real scene) and `click_driver` (synthesized clicks + occlusion audit). Both caught genuine shipped bugs.
- **Gap:** click-driver covers **4 stations of ~12** — no forges, no level-up ceremony, no combat, no travel.
- No performance test, no visual regression, no first-launch/backend-down test.
- **Effort:** M.

---

## 2. The vertical-slice task list

Only work that improves the player's first complete experience. Grouped by
theme, each item independently shippable.

### A. Continuity — the seams *(highest perceived-quality density)*

| # | Task | Effort |
|---|---|---|
| A1 | Scene transition system: world-skinned fade/wipe on all 6 scene changes | M |
| A2 | Loading experience: render the `Loading` FSM state — world art, a lore line, a real progress beat while hydrate + first art warm | M |
| A3 | Tab/page transitions inside THE MENU and the Lore Book | S |
| A4 | Forge stage transitions (content slides, rail advances) | S |
| A5 | Travel as a moment: map animation or journey card, "two days pass" beat | M |
| A6 | "The GM is thinking" state during first-token wait | S |

### B. Audio — from silent to felt

| # | Task | Effort |
|---|---|---|
| B1 | UI feedback set: hover, click, open, close, back (synthesize via `make_sfx.py`) | M |
| B2 | Reward audio: equip, purchase, loot, level-up fanfare, quest complete | M |
| B3 | Beat audio: page turn, dice settle (exists), travel departure, save | S |
| B4 | Combat audio states: turn start, crit, defeat | S |
| B5 | Audio mixer bus + per-category volume in Settings | S |

### C. Legibility & guidance

| # | Task | Effort |
|---|---|---|
| C1 | Tooltip pass: every actionable control in the game (currently 6 total) | M |
| C2 | Purge the 24 remaining rendered glyphs — including `⏳`/`✅`/`✕` inside `myth_forge_step.gd` | S |
| C3 | Action-bar redesign: 12 flat buttons → grouped, labeled, prompt-aware | M |
| C4 | Empty-state pass: every list/tab that can be empty gets composed copy + art | M |
| C5 | Human error copy: no raw HTTP statuses (`Login failed (0)`), no engineering nouns | S |

### D. Ceremony — making outcomes feel earned

| # | Task | Effort |
|---|---|---|
| D1 | Level-up ceremony beat (burst, sound, the star flaring on Destiny) | M |
| D2 | Combat victory/defeat presentation | M |
| D3 | Hero-forged reveal (composed frame: portrait, name, class, world) | M |
| D4 | Chapter/THE END completion ceremony | M |
| D5 | Loot & reward presentation (item art, rarity flourish) | S |

### E. Robustness of first impression

| # | Task | Effort |
|---|---|---|
| E1 | Backend-down first-launch: a painted "the realm sleeps" screen with retry, not a login error | M |
| E2 | Art-unavailable placeholders (painted frames, not blanks) | S |
| E3 | Save visibility: autosave indicator + explicit confirmation | S |
| E4 | LLM failure/timeout copy in the GM's voice | S |

### F. Theming completion

| # | Task | Effort |
|---|---|---|
| F1 | Materials across all remaining panel surfaces | M |
| F2 | Vendor stock for the 5 missing families | M |
| F3 | World-skinned title banner + menu art per family | S |

### G. Accessibility & input

| # | Task | Effort |
|---|---|---|
| G1 | Text scaling (theme font-size multiplier in Settings) | M |
| G2 | WCAG contrast measurement + fixes across all 8 palettes | S |
| G3 | Controller: forge rail, combat spell links, menu tab cycling | M |
| G4 | Button-prompt glyphs when a pad is connected | M |

### H. Confidence

| # | Task | Effort |
|---|---|---|
| H1 | Extend click-driver to forges, combat, level-up, travel | M |
| H2 | Performance profile: frame budget, the 8 per-frame loops, art memory | S |
| H3 | First-launch / backend-down automated test | S |
| H4 | Doc hygiene: FeatureMatrix + Roadmap catch-up (Backlog §8) | S |

**Total: 38 tasks — roughly 6–8 sprints at this cadence.**

---

## 3. Recommended next sprint (ONE)

# Sprint VS-1 — "No Seams, No Silence"

**Thesis:** the fastest, largest gain in perceived production value is not a
new system — it is removing the two things that constantly announce *this is a
prototype*: **hard cuts** and **silence**. Every player encounters both within
fifteen seconds of launching, and encounters them again at every screen change
for the entire session. Nothing else in this document is felt as often.

**Scope — tasks A1, A2, A3, A6, B1, B2, B3, C5, E1:**

1. **Transition system** — one shared `MythTransition` (world-skinned fade/wipe,
   reduce-motion aware) on all six scene changes, plus tab and forge-stage swaps.
2. **Loading experience** — the `Loading` FSM state finally renders: world key
   art, a line of the world's own lore, and honest progress while hydration and
   the first paintings warm. Play should never cut to a half-built screen again.
3. **UI + reward audio layer** — hover, click, open, close, back, equip,
   purchase, loot, level-up, page, travel, save. Synthesized through the
   existing `make_sfx.py` pipeline; wired through a small `Sfx.ui()` helper so
   every MythButton gets it for free.
4. **"The GM is thinking"** — a composed waiting state during the first-token gap.
5. **Human error copy + backend-down screen** — the first screen a stranger sees
   must never read `Login failed (0)`.

**Why this and not something else:**

- *Dialogue* (55%) is the biggest single-system gap, but it's an L-effort system
  rebuild — the wrong shape for the first vertical-slice sprint, and it would
  still ship into a silent, hard-cutting game.
- *Combat readability* matters, but a player meets combat once in the first ten
  minutes; they meet transitions and silence a hundred times.
- Audio is the highest-leverage item in the build: score 30%, effort M, and the
  synthesis pipeline already exists.

**Explicitly NOT in this sprint:** dialogue UI, quest journal, combat ceremony,
accessibility, controller work, theming sweep. They are queued, not forgotten.

**Definition of done:** a stranger can launch with the backend down, be told so
kindly, start it, forge a hero, and reach their first scene — and at no point
does the screen cut, sit silent on a click, or show an engineering string. Both
harnesses green; click-driver extended to cover the transition states.

**Estimated effort:** one full sprint (comparable to the batch work of
2026-07-21, but weighted toward craft over breadth).

---

## 4. Scoring method (so these numbers stay honest)

Every score above is backed by reading the code, not by memory:
line counts, `Sfx.play` call-site census, `tooltip_text` census, a codepoint
scan for rendered glyphs, `change_scene_to_file` census, `_process` loop
census, and the Settings screen's actual contents. Where a system is
**unmeasured** (Performance) the score reflects that uncertainty and says so.

Re-audit at the end of every sprint; a system may only move up when the
*player-visible* result improves, never because code was refactored.
