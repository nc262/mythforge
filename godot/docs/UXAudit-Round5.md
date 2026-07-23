# UX Audit — Round 5 (played, not read)

**Date:** 2026-07-22 → 07-23 · **Build:** `dist/Mythforge.exe` 19:09, four baked
worlds, `AUTH_ENABLED=false` · **Method:** launched the shipped exe, maximised,
and played it as a first-time player. No code was read until a defect was
confirmed on screen; code is cited only to explain a root cause.
**Screenshots:** `docs/audit/round5/*.png` (numbered, referenced per finding).

Reviewed as Creative Director / UX Director / Art Director / QA Lead, against
the bar the Director set: *a player must never think "this is a prototype."*

---

## 0. The verdict in one paragraph

Mythforge has **AAA raw material and pre-alpha assembly**. The painted forge
backdrops, the world-true item art, the pirate-world writing (Gallows Quay,
The Leaning Lantern, "20 doubloons in the purse"), and the character portraits
are genuinely at the level the Director is aiming for — Larian would ship that
art. But the containers around them fail: **the flagship "Forge a World" flow
is broken end-to-end**, **two in-play panels cannot be closed at all**, one
main-menu destination is entirely dead, choice cards leak their text outside
their own borders on every screen that uses them, and the world skin recolours
the whole UI to a single hue and then drops photographic backgrounds behind
body text with no scrim. The game currently reads as a prototype not because
it lacks art, but because **the art it already has is undermined by the
chrome, and three separate flows dead-end.**

**Counted this session:** 5 blocking defects, 8 distinct button treatments,
6 different words for "go forward", 4 different words for "exit", 3 screens
whose only job is to announce an unshipped feature, 0 fullscreen option.

---

## 1. Screens visited

| # | Screen | Reached via | Shot |
|---|--------|-------------|------|
| 1 | Main Menu | launch | `01` |
| 2 | Settings | menu | `02` |
| 3 | Chronicles (empty) | menu | `03` |
| 4 | The Campaign Shelf | menu → CAMPAIGNS | `04` |
| 5 | World Forge — The Spark | menu → FORGE A WORLD | `05` |
| 6 | World Forge — Raise the Pillars | Spark → To the pillars | `06` |
| 7 | World Forge — The Forging (wait) | Strike the world | `07` |
| 8 | World Forge — failure | 2.5 min later | `08` |
| 9 | Character Forge — The Cold Anvil | menu → FORGE A HERO | `09` |
| 10 | Character Forge — Choose Your Origin | Light the forge | `10` |
| 11 | Character Forge — Choose the Ruleset | Continue | — |
| 12 | Character Forge — Choose Your Heritage | Continue | `11` |
| 13 | Character Forge — Choose Your Class | Strike | `12` |
| 14 | Character Forge — Choose Your Background | Strike | — |
| 15 | Character Forge — Your Nature | Strike | `13` |
| 16 | Character Forge — Their Face, In Words | Strike | `14` |
| 17 | Character Forge — The Voice | Strike | — |
| 18 | Character Forge — Choose Your Kit | Continue | — |
| 19 | Character Forge — The Quenching | To the Quenching | `15` |
| 20 | Adventure Forge — The Table Is Set | menu → BEGIN A NEW ADVENTURE | — |
| 21 | Adventure Forge — Who Plays Tonight? | Sit down | `16` |
| 22 | Adventure Forge — Which World? | Next | — |
| 23 | Adventure Forge — Which Tale in Saltmarsh Reach? | pick world | `17` |
| 24 | Adventure Forge — The Party / Difficulty / House Rules | Next ×3 | — |
| 25 | Adventure Forge — The Adventure, Previewed | Next | `18` |
| 26 | **Duplicate Quenching over the live game** | Begin the adventure | `19` |
| 27 | Session Zero modal | Begin the adventure (2nd) | — |
| 28 | Play screen (Exploration) | Begin the adventure (3rd) | — |
| 29 | The Record of Corin Vale — Gear | bag / Sheet | — |
| 30 | — Record · Skills tabs | tab bar | — |
| 31 | Lore Book — The Lore of Saltmarsh Reach | action bar | — |

### Not exercised — and why

Honest gaps, so this document is not read as complete coverage:

- **Vendors / Combat** — both are GM-driven events. The opening narration alone
  took the local model long enough that a shop or an encounter could not be
  reached inside the session. **Untested.**
- **Forge a Campaign · Forge a GM · Forge a Companion · A Quiet Table** — not
  entered. (`A QUIET TABLE` is in fact *unreachable* at this window size, see
  UX-02.)
- **Continue an Existing Adventure** — could not be tested, because the run
  ended trapped inside the Lore Book (BLK-05) and there is no Continue entry
  on the main menu to begin with (UX-01).
- **Audio** — a screenshot cannot hear. Sound is excluded from every finding;
  "missing sound" is listed only as an *open question* in §7.

---

## 2. Blocking defects (P0) — these are bugs, not polish

### BLK-01 · Forge a World fails, every time, after ~2.5 minutes of dead air
**Shots:** `07`, `08` · **Severity: Critical** — the flagship feature does not work.

Struck a Pirates world with the premise *"A drowned pirate archipelago of
storm-cursed wreckers, ghost-lit reefs and salvage captains."* The Forging
screen held for 2 min 30 s with no spinner, no progress, no cancel, then
returned to Raise the Pillars with, at the very bottom of the screen in body-grey:

> The forge sputtered (200) — strike again.

**Root cause (evidenced, not guessed).** The backend log shows the request
*succeeded*: six sequential LLM calls, 19:37:02 → 19:39:29 (26.3s, 39.7s,
37.2s, 12.1s, 24.7s, 6.7s), and `POST /api/characters/studio/worldsmith → 200 OK`.
The client's guard is `if w.get("_status") != 200 or str(w.get("name","")) == ""`
(`scenes/forge/world_forge.gd:198`). Status *was* 200; the payload had **no
`name`**. So worldsmith returns 200 with a body the client cannot build a
world from, and the error string then prints the HTTP status — which is why
the player is shown the nonsensical "(200)".

**Player-visible consequence:** ~2.5 minutes and six model calls burned, no world.

**Fix:** surface the real reason (empty/invalid worldsmith payload) instead of
the HTTP status; make the endpoint fail loudly server-side when it cannot
produce a `name`. **Effort:** S to correct the message, M to fix the payload
contract. **Depends on:** the `complete_json` / `_TIMEOUT_EXEMPT_PREFIXES`
contract already documented in `SESSION-HANDOFF.md §3`.

### BLK-02 · "Strike again" does not work — the World Forge is a dead end
**Shot:** `08` · **Severity: Critical**

The error tells the player to strike again. Striking again produced no visible
change whatsoever (verified at +3 s and +20 s; the button showed its hover
state, so the control is live). The backend log confirms a **second**
`POST /api/characters/studio/worldsmith → 200 OK` with **no LLM calls behind it** —
it failed instantly and re-rendered the identical error, which is
indistinguishable from a dead button. The only exit is "leave the table".

**Fix:** a real retry state (disable + "striking again…"), and a distinct
message on repeat failure. **Effort:** S. **Depends on:** BLK-01.

### BLK-03 · The Campaign Shelf is completely inert
**Shot:** `04` · **Severity: Critical**

Eight tales, each with a "Set the table with this tale ›" call to action.
Clicked the card body, the CTA text, and the chevron — three targets, then
waited 55 s. Nothing. No navigation, no error, no loading state. The cards
also have **no hover response at all** (the main-menu buttons do), so there is
no feedback that they are interactive in the first place.

An entire main-menu destination does nothing. **Effort:** M (needs the same
"set the table" wiring the Adventure Forge already has). **Depends on:** the
tale→adventure binding in `adventure_forge._begin`.

### BLK-04 · The character sheet ignores ✕ and Escape
**Severity: Critical**

Clicking ✕ (top-right) and pressing Escape both left "The Record of Corin
Vale" open. The **only** control that closed it was "Return to the tale" —
which is **clipped by the bottom of the window** (roughly half the button is
off-screen). A player who does not guess to click a half-visible button is
stuck in the sheet.

### BLK-05 · The Lore Book cannot be closed at all
**Severity: Critical** — this ended the play session.

"Close the book" (clicked at two points), Escape — none of them close it. The
run terminated trapped inside the Lore Book with the game unusable. This is
the single worst defect found: it is unrecoverable without killing the process.

**Fix for BLK-04/05 together:** one modal-dismiss contract — Escape closes the
topmost panel, ✕ and the labelled control call the same handler, and no
dismiss control may sit outside the viewport. **Effort:** S–M. **Depends on:**
a shared panel base (does not exist yet — that *is* the fix).

---

## 3. Flow / UX findings

| ID | Finding | Sev | Root cause | Improvement | Effort |
|----|---------|-----|-----------|-------------|--------|
| UX-01 | **No CONTINUE on the main menu.** The returning player's first need is absent; the only way back into a tale is Chronicles or re-forging. | High | Menu is a feature index, not a player-state surface | Continue as the first, default-focused entry, with the tale name + world art on it; hide when there is no save | M |
| UX-02 | **The menu overflows and does not scroll.** "A QUIET TABLE" is clipped at the bottom edge; scrolling does nothing. That entry is **unreachable**. | High | Fixed column, no scroll container, 11 top-level items | Cut to 5–6 entries (below) | S |
| UX-03 | **Eleven top-level menu entries**, four of them "FORGE A ___", plus CAMPAIGNS *and* CHRONICLES. | High | Taxonomy exposed as navigation | Continue · New Adventure · The Forges (submenu) · Library (Campaigns+Chronicles+Worlds) · Settings · Exit | M |
| UX-04 | **Creation ends in a dead menu.** Banking Corin Vale returned to an unchanged main menu — no toast, no roster, no "play with them now". The hero is invisible until Adventure Forge stage 2. | High | No post-creation destination | Land on a hero card with "Begin an adventure with Corin Vale"; add a Roster surface | M |
| UX-05 | **You confirm your hero twice.** Preview → *BEGIN THE ADVENTURE* → the Character Forge Quenching re-opens **on top of the running game** (shot `19`) → *BEGIN THE ADVENTURE* → Session Zero → *Begin the adventure*. Three "begin" clicks. | High | `game._open_character_forge` re-enters at the Quenching for a `pending_hero` that is already complete | Skip the Quenching when the pending hero is fully forged and named | S |
| UX-06 | **Session Zero duplicates the Adventure Forge.** Difficulty, house rules and companions were just set; Session Zero then asks for tone/grit/pace/rules again, in a completely different visual language. | High | Two tone systems, neither aware of the other | Fold Session Zero's sliders into the Adventure Forge's House Rules stage | M |
| UX-07 | **Terminology drift.** campaign / tale / premise / adventure / chronicle / story / record all name overlapping things. "Chronicle" is a tab in the sheet *and* in the Lore Book *and* a main-menu entry. "Campaigns" appears in three places. | High | No lexicon | Pick three words and enforce: **World**, **Tale**, **Chronicle**. Everything else is a synonym to delete | S (doc) + M (sweep) |
| UX-08 | **Six verbs for "next"**: To the pillars › · Light the forge › · Continue › · Strike › · To the Quenching › · NEXT — THE PARTY. **Four for "exit"**: leave the table · bank the fire · LEAVE THE TABLE · ‹ Menu. | Med | Per-screen copy, no pattern | One forward verb per forge (ceremonial is fine — *consistent* ceremony), one exit word everywhere | S |
| UX-09 | **Three stages exist only to announce missing features:** Ruleset (2 of 3 cards are "a future forging"), The Voice ("the voice provider sleeps"), The Party (one toggle + "party multiplayer — is a future forging"). | Med | Shipped scaffolding | Hide unshipped stages; 11 steps → 8 | S |
| UX-10 | **Silent dead tabs.** In the sheet, Atlas and Chronicle render dim and clicking them does nothing — no empty state, no explanation. | Med | No empty-state contract | Every tab shows an empty state or is hidden | S |
| UX-11 | **The tab bar shifts position between tabs**, so a second click lands on dead space; "The Table" clips to "The Tab" at the right edge. | Med | Tabs sized by active-label width | Fixed tab widths | S |
| UX-12 | **Chronicles is a dead end**: "begin an adventure and its story is kept here" with no way to begin one from that screen. | Med | Empty state has copy but no CTA | Empty states carry the action they describe | S |
| UX-13 | **No fullscreen.** Alt+Enter does nothing and Settings has no Video section at all (GM / Sound & Motion / Account only). | Med | Not implemented | Video section: fullscreen, resolution, UI scale | S |
| UX-14 | **"Sign out" in a build with `AUTH_ENABLED=false`.** A control for a system the player never used. | Low | Not gated | Hide when auth is off | XS |

---

## 4. Visual quality & art findings

| ID | Finding | Sev | Root cause | Improvement | Effort |
|----|---------|-----|-----------|-------------|--------|
| VIS-01 | **Choice cards leak their own text outside their borders.** Confirmed on Heritage (`11`: "25 ft", "30 ft" render *below* the card), Class (`12`: every hit-die label floats between rows; "arrow" escapes the Ranger card), Background (4 of 8 skill lines outside the card), Which World? ("2 tales + free roam" outside all four cards). | **High** | The choice-card component does not contain its `foot`/body at fixed height | Fix the card once: min-height from content, clip + ellipsis, `foot` inside the border | S — **highest ratio in the audit** |
| VIS-02 | **Mid-word truncation with no ellipsis.** Class cards cut at "answer them i", "mock their w"; Which World? cuts "quiet adventu", "sleeps or for"; House Rules placeholder cuts at "(or leave the table's r". | High | Fixed-height clip; `.left(60)` truncation (mine, `adventure_forge.gd`) | Word-boundary truncation + "…"; two-line clamp | S |
| VIS-03 | **Eight button treatments** across the app: wood-plate menu rows · flat-purple menu rows · gold brass (`SIT DOWN`) · leather outline (`LEAVE THE TABLE`) · ghost outline (`Strike ›`) · bare text (`bank the fire`, `Re-strike the portrait`, `Close the book`) · flat filled (`Envision this hero`) · **stock Godot** (`Reroll destiny`). Bare-text controls do not read as controls. | **High** | No button contract | Three tiers only — primary (brass), secondary (leather), tertiary (underlined text with a hit area). Delete the rest | M |
| VIS-04 | **Icons carry no information and collide.** 9 heritages share one shield. 12 classes share 4 glyphs. 8 backgrounds share one. 4 difficulties share one. On Raise the Pillars, Intrigue = Norse and Pirates = Sci-Fi. High Fantasy's own subtitle says "bright banners, old dragons" and its icon is a mountain. | **High** | Glyph set smaller than the taxonomies using it | Either a real 1:1 glyph set, or drop icons where they are duplicated — a wrong icon is worse than none | M |
| VIS-05 | **The Campaign Shelf has zero imagery** (`04`) — eight tales as flat text rows, on the screen where the player picks their story. Every world already has key art. | **High** | Art pipeline not wired to this screen | World key art as a card banner, grouped under world headers | S |
| VIS-06 | **Origin heroes have no portraits** (`10`). Brakka, Elara, Finch, Sister Maren — four named characters as text in navy boxes, with duplicate glyphs. This is Larian's marquee moment. | **High** | Portraits never generated for the four pre-mades | **Pre-generate and ship four handcrafted portraits.** No runtime cost, largest perceived-quality jump per hour of work | S |
| VIS-07 | **The heritage preview renders as a bare empty rectangle** when art is not cached (`11`) — and the default selection on arrival (Halfling) is exactly one of the uncached ones, so the *first* thing the player sees is a blank purple box. Cached races (Human, Dragonborn) look excellent. | **High** | No skeleton/placeholder state; no pre-bake | Pre-bake all 9 heritage portraits into the exe; frame the slot; skeleton shimmer while painting | S |
| VIS-08 | **No dice.** "Your Nature" reports `Destiny: 15, 14, 13, 10, 10, 9` as plain text — no roll, no animation, no ability names. The player never sees STR/DEX/CON until the sheet, after creation. | High | Stage renders data, not an event | Show the six scores mapped to abilities, rolled | M |
| VIS-09 | **The Forging wait screen is a static title and one line**, for a wait it calls "about a minute" and which actually runs minutes (`07`). No spinner, no stages, no cancel, nothing to look at — in the ritual the game is *named after*. | **High** | No loading-state system | Stage-by-stage narration ("naming the coasts… seeding the bestiary…"), an anvil/spark loop, lore cards, and a cancel | M |
| VIS-10 | **The play screen is a text box on black** — ~400 px of empty void below the narration, an **empty outlined rectangle** where the minimap should be, no HP bar, no gold, no portrait, no companion strip. HP is mentioned in prose only. | **High** | Scene art and HUD not built for Exploration | Scene illustration + a real HUD (portrait, HP, gold, time) | L |
| VIS-11 | **Session Zero is a stock Godot dialog** — mid-grey panel, plain ✕, five default HSliders — dropped into a themed game at the first moment of play. | High | Never themed | Theme it, or fold into House Rules (UX-06) | S |
| VIS-12 | **The Lore Book calls itself "the world's illustrated encyclopedia" and contains no illustrations.** Three entries, each a large card with a title, a one-word type, and ~120 px of blank space. | High | Entry art + descriptions not generated | Generate/ship place art + one-paragraph descriptions | M |
| VIS-13 | **The adventure preview is a flat purple box with three lines of text** (`18`) — no hero portrait, no world art, no tale hook, on the last screen before hours of play. Both assets exist. | High | Composed as a summary, not a splash | Portrait + world banner + tale title | S |
| VIS-14 | **World key art is a ~64×48 thumbnail** on the Which World? cards — beautiful full-bleed images shown at postage-stamp size, making the cards top-heavy. | Med | Card art slot sized as an icon | Full-width card banner | S |
| VIS-15 | **11 empty equipment slots are identical grey diamonds.** Diablo/Blizzard use ghosted silhouettes per slot. | Med | One placeholder glyph | Per-slot silhouettes | S |
| VIS-16 | **HP bar is red at full health** (12/12). Red reads as danger. | Med | Static colour | Colour ramp green→amber→red | XS |
| VIS-17 | **The Quenching undersells eleven stages of investment** (`15`) — the payoff is one 12 px grey line: "Human Fighter · Soldier · destiny: … · kit: …". | Med | Summary as a label | A hero card: portrait, name, the six scores, kit icons | M |
| VIS-18 | **Layout shift when art lands.** On Appearance, the portrait appears in previously-unreserved space and shoves the composition sideways, ending ~9 px from the "Envision this hero" button (`14`). The Quenching backdrop faded in ~30 s after the screen appeared, leaving a black void first. | Med | No reserved art slots, no fade | Reserve the frame; cross-fade in | S |
| VIS-19 | **Text inputs are stock, and single-line where the content is a sentence.** The Spark's LineEdit scrolls the premise out of view as you type; its own example wraps to two lines. Typo in that example: "hopeful.." | Med | LineEdit used for prose | Multi-line, themed field | S |
| VIS-20 | **Settings is a Windows settings page** — full-width rows, an unlabelled stock volume slider with no value readout, stock toggles, ~50 % dead space. | Med | No layout system on this screen | Constrained centred panel, labelled slider with value | S |
| VIS-21 | **Four faint grey disclosure lines** ("Advanced: shape the five pillars by hand", "Make this path your own", "Your story, in your words", "Or take the standard array") are the power-user paths and are nearly invisible, several sitting directly on bright background art. | Med | Styled as footnotes | Real expander control with a scrim | S |
| VIS-22 | **Crest/wordmark clipped** at the top of the main menu; the stage rail's diamonds sit tight against the window chrome on every forge. | Low | No top safe-area | Safe-area padding | XS |

---

## 5. Readability & world-skin findings

The single most damaging cluster, because it hits the most-used screen.

| ID | Finding | Sev | Root cause | Improvement | Effort |
|----|---------|-----|-----------|-------------|--------|
| RD-01 | **The world skin recolours the entire UI to one hue.** Entering Saltmarsh turned every element yellow-on-black: title, all 11 action-bar glyphs, the minimap outline, the input border, the Quenching's gold ring, the stage rail. No secondary colour, no fills — it reads as a monochrome terminal, not a nautical world (`19`). | **Critical** | Skin applies an accent to everything rather than to accents | A skin sets *accent + backdrop*, not every foreground colour. Lock neutrals and text to the base theme | M |
| RD-02 | **Equipped item names are dark green on a light tan panel** — "Splintered Shorewood Fishhook-Edged Cutlass" is effectively unreadable (verified at 3× zoom). | **Critical** | Skin accent used as body-text colour over a light panel | Contrast floor enforced at the token level (AA 4.5:1) | S |
| RD-03 | **World-skin photographs load behind body text with no scrim.** In the sheet, a sunlit ship's-cabin image fades in and "Passive Perception", "Hit Dice", "Proficiency", the Gear slot labels, and half the Skills list become unreadable over bright water and window. The panel was perfectly legible 30 s earlier. | **Critical** | Backdrop composited under content without a scrim | Mandatory scrim/vignette behind any text over generated art | S |
| RD-04 | **The Lore Book panel is translucent** — the play screen's narration shows through its left edge, and entry cards sit directly on the desk photograph. | High | Panel alpha | Opaque panel or heavier scrim | XS |
| RD-05 | **Narration line length is ~150 characters** (a 1024 px box) — roughly double the comfortable measure, at ~13 px, for the game's primary content. | High | Box stretches to the window | Clamp the reading column to 60–75 characters | XS |
| RD-06 | **Body text sits over busy art with no plate** on the World Forge's Spark stage — the example line is unreadable against the candle-lit table. | Med | No content plate | Scrim behind the content column | S |
| RD-07 | **Error text is styled exactly like body copy**, placed ~250 px below the control that caused it, at the very bottom of the screen. Easy to miss entirely after a 2.5-minute wait. | High | No error style/placement rule | Errors adjacent to their control, in an error colour, with an icon | S |

---

## 6. World immersion — what actually works

This section is deliberately positive, because the audit would be misleading
without it. **World theming is the strongest system in the build:**

- Items are world-true: *Splintered Shorewood Fishhook-Edged Cutlass*,
  *Breastplate of Rusting Bands*, and real per-material icons in the pack.
- Currency is world-true: **"20 doubloons in the purse"**, not "gold".
- The sheet's backdrop is a ship's cabin; the Lore Book's is a chart desk.
- The opening prose is excellent and specific: Gallows Quay, The Leaning
  Lantern, Samuel 'Sanddollar' Jenkins, "the tide waits".
- Lore Book places are world-true: The Sunken Fort, Gallows Quay.

**Where the world stops reaching:**

- **The Character Forge is world-blind.** Kits are "longsword, oak shield,
  leathers" regardless of world; heritages and classes are generic fantasy in
  a pirate campaign.
- **The Saltmarsh default world has no tale hooks.** Both its tales render
  with no premise text — as blank cards on the Campaign Shelf (`04`) and, in
  the Adventure Forge, as three *identical* cards sharing one image and the
  same body line "wander it as you please" (`17`). The default world's story
  choice is meaningless. (The identical fallback body is mine, from today's
  two-step flow — it hid a data hole instead of exposing it.)
- **No map.** The minimap is an empty rectangle; the Atlas tab does nothing.

---

## 7. Open questions (cannot be settled from screenshots)

1. **Audio** — are there button, page-turn, dice, forge and combat sounds? The
   Settings toggles imply yes. Needs a listening pass.
2. **Motion** — hover scale is present on menu rows and pillar tiles; whether
   transitions between forge stages animate could not be judged from stills.
3. **Vendors and combat** — entirely untested (see §1).
4. **Legacy heroes** — Quin and Sister Maren show no portrait on the roster
   (`16`) because they were banked before today's `bank_hero` id fix. Corin
   Vale, banked after, shows correctly. A one-time migration is needed, or
   they stay faceless until re-banked.

---

## 8. Root-cause summary — five roots under ~45 findings

1. **No shared panel/modal contract.** → BLK-04, BLK-05, UX-10, UX-11, RD-04.
2. **The choice-card component does not contain its content.** → VIS-01,
   VIS-02, and most of the "clipping" complaints. One component, ~six screens.
3. **The world skin has no contrast or scope rules.** → RD-01, RD-02, RD-03,
   RD-06. It paints foregrounds it should not touch and composites art under
   text without a scrim.
4. **No loading/empty/error state system.** → BLK-01's dead air, BLK-02,
   VIS-07, VIS-09, UX-12, RD-07.
5. **The art pipeline is not wired to the screens that need it most.** The
   assets exist; the Campaign Shelf, origin heroes, preview, Lore Book and
   kit cards do not use them. → VIS-05, VIS-06, VIS-12, VIS-13.

Fix those five and roughly two-thirds of this document closes.
