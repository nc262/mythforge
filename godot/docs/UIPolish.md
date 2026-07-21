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

1. **Data/copy bugs** (cheap, high-trust): HP double-print, XP string,
   proficiency dedup, header world id, currency unification, Armour/tap.
2. **Gear-tab consolidation** (the keystone): pack grid into Gear, retire
   flat-lay, sidebar readout, one worn/ghost treatment, slot arc + no overlap.
3. **Render treatment**: frame/grade + identity-true prompt inputs.
4. **Lore Book**: content-height entries, kind chips, tab scrim, scroll fade.
5. **Play screen**: empty state, composed recap, drawn HP bar, action row.
6. **Global**: contrast pass, art grading/framing utility for all AI images.

Rounds 3+ append below as screenshots arrive.
