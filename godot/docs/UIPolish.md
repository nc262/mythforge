# UI Polish Backlog — screenshot audit (2026-07-20)

Built from live playtest screenshots with the Director. Each round adds a
10-wrong / 10-improve pair; items graduate to ✅ with the commit that fixes
them. **Keystone decision (Director): the Gear tab's 13-slot paper doll IS
the inventory — the pack flat-lay window and duplicate lists retire into it.**

## The diagnosis (holds across all screens)

The chrome got a design system; the content never did. Three recurring roots:
1. **Raw engine strings shipped as UI copy** (world ids, taxonomy kinds,
   shorthand like "sell 3", transcript dumps, duplicated readouts).
2. **Generated art used raw** — no framing, no palette grading, no per-world
   style contract; item icons collide, backdrops clash, renders ignore
   identity/world.
3. **Three competing inventory systems** (sidebar list · pack flat-lay ·
   Gear doll) — no single source of truth; the best one is buried deepest.

## Round 1 — play screen + pack window

Wrong: proficiency list duplicates entries · recap dumps raw truncated
transcript · world id in header ("· everyday") · "Gold 16" vs "16 cash" ·
modal double-chrome + scrim bleed · ability grid inconsistent (CHA inline
mod) · item icon collisions (one art, several items) · "sell 3"/"Slots: L1
2/2" shorthand · focus ring at rest on "Put the pack away" · center of play
screen is a scrimmed void.

Improve: grade + frame AI backdrops to world palette · design the empty chat
state (bright scene, composed recap card, prompt) · sidebar spacing scale +
3–4 grouped sections · drawn HP bar (kill the ▰▱ font glyphs) · quick actions
→ proper icon row · one empty-slot ghost treatment (13-slot doll layout) ·
hints → affordances (drag handles, hover targets) · contrast bump one step ·
recap composed in GM voice via the language guard · pack status strip
(fill + purse + AC/HP/Attack) with drawn icons.

## Round 2 — Lore Book (Places) + Record/Gear tab

Wrong: HP bar prints "HP 9/9 9/9" twice · "XP → level 2 0/100" reads as
20/100 · equipped names ghost-faded (read as disabled) · 4-slot list beside
13-slot doll in ONE window · doll render overlaps slot labels + AC caption ·
render ships its studio-gray backdrop hard-edged over the env · render is a
plate knight for a modern-world cleric (prompt ignores identity/world) ·
"Armor" vs "Armour Class", "tap" on desktop · Lore Book leaks lowercase
"tavern/home/landmark/wilds" + The Office wears park art + 4 art styles in 4
cards · lore entries are nested card-in-card, ~80% empty, Chronicle tab
unreadable over the lamp, last entry clips with no scroll affordance.

Improve: **doll = THE inventory** (pack grid merges into Gear tab; flat-lay
window retires; sidebar shrinks to readout) · body-mapped slot arc, labels
never occluded · render framed: backdrop faded, forge border, palette grade,
re-render as a real button · render prompt = WorldSkin style + class + race +
appearance + equipped · drawn HP/XP bars with composed labels · world-skinned
kind chips (mug/house/pillar/tree icons; "Café" in Everyday, "Tavern" in
Embervale) · lore entry = content-height row with art, chip, line, action
("Set off →") · scrim strip behind the Book's tab rail · one codified "worn"
treatment (gold ring + full-ink name + tag) · glossary sweep: currency(),
armor spelling, click verbs.

## Execution order (each its own commit, harness-gated)

1. ✅ **Data/copy bugs** (cheap, high-trust): HP double-print, XP string,
   proficiency dedup, header world id, currency unification, Armour/tap.
2. ✅ **Gear-tab consolidation** (the keystone, `70d2a5c`): pack cards merged
   into the Gear tab, flat-lay window deleted, sidebar → compact HUD
   (vitals + castable/usable only), HUD repaints when the menu closes.
3. ✅ **Render treatment** (`ec6b716`): forge-bordered plate, backdrop faded
   into the panel, palette grade, identity-true prompt (world fashion always).
4. ✅ **Lore Book** (`ec6b716`): world-skinned kind chips (place_kind vocab +
   drawn icons), tab-rail scrim, bottom scroll fade.
5. ✅ **Play screen** (`ec6b716`): bright empty-state scene, composed recap
   ("Previously, in <tale>…", sentence-boundary cuts), drawn HP bar image.
6. ✅ **Global**: `MythPlate` (ui/myth_plate.gd) is THE shared frame for AI
   art — forge border, cover-fit, palette grade, base fade, live art-key
   binding; used by the doll render, item inspect, shop detail. Contrast
   pass: `ink_dim` lightened one step in all 8 palettes. Material surfaces:
   stone/parchment generators + per-family `panel`/`page` roles (menu hero
   panel + Lore Book pages wear real materials).

## Round 3 — merchant window + atlas/map modals

Wrong: purse "cash" vs prices "gold" vs unitless "sells 3" in ONE window ·
vendor stock ignores world skin (daggers in the Everyday corner shop) · the
Everyday world chart is a vintage EARTH map (apartment pinned mid-Atlantic) ·
AI-gibberish banner text + triple compass roses shipped raw · pins are tiny
unlabeled "?" dots, no you-are-here, no click affordance · map only reachable
via a link inside a chat bubble (✅ fixed by the atlas fold in current build) ·
shop is text-only — zero item art on the items screen · Buy/Sell/Haggle three
identical bars (a skill check dressed as a primary action) · "Leave the
counter" floats detached w/ resting focus ring; purse label clipped into the
title bar · quick-action row under the portrait reads as wrapping footnote
links, not buttons (Director: "doesn't fit AAA" — promoted to phase 2).

Improve: one currency pipe (every price/sell string via currency()) ·
world-skinned vendor stock tables · chart prompt = world name + family flavor
+ scale + real locations (never "world map") · real pins (label, you-are-here,
hover, ring fallback when coords unknown) · in-panel map header replaces the
floating dialog title · map gets a toolbar slot (wartable icon) · shop rows
with painted item art + price chips; serif section headers · Buy/Sell primary
under lists, Haggle a ghost one-liner with die icon + DC, disabled after use ·
selected-item detail strip (art, buy price, sell value) so 40/3 reads as a
fence's lowball not a bug · portrait rail → real drawn-icon MythButtons.

Round 3 status: **ALL CLOSED.** currency pipe ✅ · chart prompt world-true ✅ ·
pins labeled w/ you-are-here + hover roads ✅ · shop item art ✅ · Buy
accent-primary / Haggle ghost+die ✅ · map in the menu (Atlas tab) ✅ ·
world-skinned vendor stock ✅ (`vendor_stock_cyber/everyday/space` tables,
names carry classifier keywords so mk_item stats them; other families fall
back to the fantasy base) · selected-item detail strip ✅ · in-panel chart
header on the Atlas tab ✅.

Rounds 4+ append below as screenshots arrive.

---

## Round 5 — full end-to-end playthrough of the shipped exe (2026-07-23)

Source: **[UXAudit-Round5.md](UXAudit-Round5.md)** — the whole game played as a
player, menu → forges → adventure → play → panels. Shots in
`docs/audit/round5/`. This round breaks the 10-wrong/10-improve format because
five findings are **blocking bugs**, not polish: they are listed first and are
not negotiable against visual work.

### The Round-5 diagnosis (adds two roots to Round 1's three)

4. **No shared panel/modal contract** — panels ignore Escape and their own ✕;
   two of them cannot be closed at all.
5. **The world skin has no scope or contrast rules** — it recolours every
   foreground to one hue and composites photographs under body text with no
   scrim, on the most-used screen in the game.

### Tier 0 — blocking. Fix before any polish.

| # | Item | Effort |
|---|------|--------|
| B1 | **Lore Book cannot be closed** (Close the book / Escape both dead) — traps the player, unrecoverable | S |
| B2 | **Character sheet ignores ✕ and Escape**; the only working exit ("Return to the tale") is clipped off-screen | S |
| B3 | **Forge a World fails every time** — worldsmith returns 200 with no `name`; 2.5 min + 6 LLM calls burned, then "The forge sputtered (200)" | S msg / M contract |
| B4 | **"Strike again" is dead** after that failure — the World Forge is a hard dead end | S |
| B5 | **The Campaign Shelf is entirely inert** — 8 tales, no hover, no click, no error; a whole main-menu destination does nothing | M |
| B6 | **No way out of a tale.** The play screen's exit (tooltip: "Close") is dead at three click points, and Escape does nothing — so Return to Main Menu and Continue are both unreachable | S |
| B7 | **The empty minimap frame floats above the transcript** and covers live story text, the combat roll bar and the "Still composing" status | S |
| B8 | **~2 minutes per turn — time-to-first-token over 60 s.** Director: unacceptable, promoted from CMB-03. Three measured causes, see below | M |

#### B8 — why a turn takes two minutes (measured, 2026-07-23 06:05–06:09)

1. **Narration runs on `qwen2.5:14b`.** There is **no `data/settings.json` on this
   box**, so every model setting is at its default (`default_model: ""`) and the
   resolver falls through to "most capable enabled text model" — the 14B. One
   narration call measured **53.53 s**. `llama3.1:8b` is installed and is what
   the fast-window extractor path already prefers.
2. **The GPU is grinding art while the player waits.** Opening the shop enqueued
   an icon job for every ware; the log shows them firing back-to-back at
   ~22–27 s each (*Chain Shirt · Shield · Helmet · Boots · Arrows · Longbow ·
   Shortsword · Handaxe · Ale · Cheese*) straight through the combat turn, plus
   repeated `candid photo of The Tide-Debt` scene jobs. Ollama and ComfyUI share
   one AMD GPU, so the narration call is starved. **This is the gap between the
   53 s LLM call and the ~2 min the player experiences.**
3. **Nothing is shown until the first token.** The client *does* stream
   (`Api.sse_delta` → `_on_delta`), so streaming is not broken — but TTFT is
   >60 s and the only feedback for that whole minute is one static grey line.

**Shipped (2026-07-23), measured on the exe, not claimed:**

| Beat | Before | After |
|------|--------|-------|
| Opening turn, same tale | **107.5 s** (qwen2.5:14b) | **68.3 s** (llama3.1:8b, *including* its cold load) |
| Mid-play turn | 53.5 s LLM — **~2 min felt**, art grinding alongside | **45.1 s**, art held |

- `Api.auto_gm_model()` — "Auto" now takes the largest model in the ≤9B window
  instead of the biggest installed. Verified in the shipped build: the new
  session logs `Context length for llama3.1:8b`. Prose quality holds (Mornin'
  Emily, Gully 'Sea Snake' Gordon, the seaweed-infused ale).
- `Art.hold` — the art queue pauses for the length of a GM stream, so the
  narrator gets the card. 180 s safety valve.

**Still open on B8.** ~45 s a turn is better, not good. What's left: a token
ceiling on GM replies (they run 3–4 paragraphs), `llama3.2:3b` for a "fast
table" option, and the perceived half — the wait is still one static grey line
with no elapsed time, and time-to-first-token is most of the turn.

Third cause found while verifying: **every tale in a world shared one save
slot** (`dm-<world>-freeroam`), so a "new" tale resumed the old session and its
old model. Fixed in `Rules.adventure_id`.

**Bonus defect found in the same log:** the world-material suffix is applied to
consumables — the shop generated *"game inventory icon of a **Ale** of salt-worn
wood, rope, and iron"* and *"**Cheese** of salt-worn wood, rope, and iron"*.

### Tier 1 — highest impact ÷ lowest effort. The most "real game" per hour.

| # | Item | Why it ranks here | Effort |
|---|------|-------------------|--------|
| 1 | **Make the choice card contain its own text** — `foot` and body render *outside* the border on Heritage, Class, Background, Which World? | One component, six screens; kills the biggest "unfinished" tell | S |
| 2 | **Scrim behind all text over generated art** | Turns three unreadable panels legible | S |
| 3 | **Contrast floor on skin tokens (AA 4.5:1)** — equipped item names are dark green on tan today | Same fix, at the token level | S |
| 4 | **Skin sets accent + backdrop only** — stop it recolouring every glyph, border and title | Removes the monochrome-terminal look from the whole session | M |
| 5 | **Pre-bake the 4 origin-hero + 9 heritage portraits** | Kills the blank-purple-box first impression; zero runtime cost; biggest perceived-quality jump available | S |
| 6 | **Three button tiers, delete the other five** | Eight treatments today; bare text doesn't read as a control | M |
| 7 | **Skip the duplicate Quenching** when the pending hero is already forged | Removes a re-confirm *on top of the running game*, and 1 of 3 "Begin" clicks | S |
| 8 | **Key art on the Campaign Shelf + adventure preview** | Both already have the images; two text screens become poster screens | S |
| 9 | **Errors next to their control, in an error style** | Today: body-grey, 250 px away, at the screen bottom | S |
| 10 | **Word-boundary truncation + ellipsis** (incl. my `.left(60)` in `adventure_forge`) | Stops "quiet adventu" | S |

### Tier 2 — high impact, real work

| # | Item | Effort |
|---|------|--------|
| 11 | **A real loading state for The Forging** — stage narration, anvil loop, lore cards, cancel. The ritual the game is named after is a static line | M |
| 12 | **Main menu: Continue first and default-focused; 11 entries → 6** — and fix the overflow that makes "A Quiet Table" unreachable | M |
| 13 | **Play-screen HUD + scene art** — portrait, HP, gold, time; the minimap is an empty rectangle and 400 px sits void | L |
| 14 | **Post-creation destination** — banking a hero lands on an unchanged menu, no acknowledgement, no way to play them | M |
| 15 | **Fold Session Zero into House Rules** — kills the stock-Godot dialog and the duplicate tone step at once | M |
| 16 | **Give the player their six abilities at creation** — "Destiny: 15, 14, 13…" is unmapped text until after the game starts | M |
| 17 | **Icon sets that match their taxonomies** — 9 heritages share one shield, 12 classes share 4 glyphs, Intrigue=Norse, Pirates=Sci-Fi | M |
| 18 | **Lore Book earns "illustrated"** — place art + a paragraph per entry | M |
| 19 | **Hide the three unshipped stages** (Ruleset alternatives, The Voice, The Party) — 11 forge steps → 8 | S |
| 20 | **Saltmarsh tale hooks** — the default world's tales have no premise text: blank on the Shelf, identical in the forge | S (content) |

### Tier 3 — consistency and finish

Lexicon: settle **World / Tale / Chronicle**, delete campaign/premise/story/
record as synonyms · one forward verb and one exit word per forge (six and four
today) · fixed tab widths (the bar shifts between tabs; "The Table" clips) ·
empty states that carry their own CTA (Chronicles tells you to begin an
adventure and offers no way to) · per-slot equipment silhouettes · HP bar
colour ramp (red at full health) · full-width world key art (64×48 thumbnails
today) · reserved art slots + cross-fade (the Appearance portrait shoves the
layout when it lands) · multi-line themed inputs (the Spark scrolls your
premise out of view; "hopeful.." typo) · Settings as a centred game panel with
a labelled volume value · a Video section with **fullscreen** (there is none) ·
hide "Sign out" when auth is off · safe-area padding (the crest clips) · clamp
the narration column to 60–75 characters (~150 today) · migrate legacy roster
heroes (Quin and Sister Maren are faceless; Corin Vale, banked after today's
fix, is not).

### Second pass — vendor, scene art, combat (all now played)

| # | Item | Effort |
|---|------|--------|
| 21 | **Paint the scene automatically on every location/beat change.** Today art only exists if the player finds an unlabelled icon and clicks "Conjure a painting" — which is why the play screen looked art-less for a whole session. Keep the button as a re-roll | M |
| 22 | **Give combat an interface.** "Roll to hit d20 +5 vs AC 13" on a bare bar is the whole of it — no initiative, no enemy nameplate or HP, no target, no player HP in view | L |
| 23 | **Land the dice.** A natural 1 prints as `*attack roll* → d20 1 +5 = 6 — critical miss!` — raw markdown, no colour, no die, no stinger, inside the player's own chat bubble | M |
| 24 | **3–4 suggested actions per beat.** The GM asks "What do you do next?" and the UI answers with an empty text box, every single turn | M |
| 25 | **Fix the vendor pack list** — four items all truncate to the same "Splintered Shoreswood…" prefix and none carry art, though the Gear tab has art for the same objects | S |
| 26 | **World-true vendor stock.** Saltmarsh's keeper sells Dagger / Handaxe / Longsword / Leather Armor while the player carries a Fishhook-Edged Cutlass. Pirate world, generic-fantasy shop | M |
| 27 | **Vendor title + ✕ render outside the panel**, on top of the story text | S |
| 28 | **Frame and centre the scene painting** — it sits left-aligned and unframed in a panel twice its width, and reflows the transcript when it lands | S |
| 29 | **Stream the GM's reply.** ~2 min per turn, arriving all at once, with one static grey line as feedback | M |

### Not covered — schedule before calling Round 5 complete

**Return to Main Menu** and **Continue an Existing Adventure** are blocked by
B6 — there is no working exit from a tale, so the round-trip cannot be tested.
**Forge a Campaign**, **Forge a GM**, **Forge a Companion** and **A Quiet
Table** were not entered. Audio was not assessed.
