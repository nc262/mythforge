# UI Redesign — AAA Direction (2026-07-16)

Directive: think Blizzard / Larian / CDPR first, Godot second. The UI must
disappear into the world. This doc is the audit, the direction, the component
library, and the phase plan. FeatureMatrix rows track every commitment here.

---

## 1. Audit — why each screen reads prototype-level

| Screen | What it is today | Why it feels like a tool, not a game | The AAA answer |
|---|---|---|---|
| **Main menu** | Forged buttons on key art, world cards | Static; nothing breathes, hover is a color swap; cards are uniform rectangles | Slow living backdrop (drift + embers), title that breathes light, cards that lift toward you on hover, staggered fade-in on entry (Diablo IV menu language) |
| **Inventory** | AcceptDialog + GridContainer of 24 outlined boxes, most empty | The empty cells ARE the spreadsheet: the player sees the data structure. Doll slots are labeled boxes in a column. Tooltips are OS-default text | A *physical pack*: only items exist as cards (no drawn empty cells), a leather capacity strap instead of a cell count, portrait-anchored paper doll with carved sockets, rarity halos, cards that lift on hover, framed comparison tooltips, right-click context, item inspection with big art (BG3/D4 language) |
| **Character sheet** | Side RichTextLabel; plaques landed last pass | Still one scrolling column; everything shouts equally; cast/equip/sell links inline like a wiki | Portrait-first hierarchy (done), grouped stat blocks, secondary info collapsible, actions grouped at point of relevance. Eventually a full Character screen with doll + 3D turntable |
| **Combat tracker** | RichTextLabel rows + urls | Text links as combat actions; initiative is a list | Action bar with icon buttons + cooldown/slot pips; initiative as portrait chips along the board edge (D4/BG3) |
| **Battle board** | Painted map, art tokens, terrain (good bones) | Tokens teleport (no motion), no hit/impact feedback on the board itself | Tween token slides, impact flashes, damage numbers rising from tokens, attack lunge micro-motion |
| **World map** | Static parchment + dots, hover lore | It's an image with circles; no zoom, no fog, no life | Pan + zoom camera, fog-of-war on unvisited marks, pulsing quest markers, animated you-are-here (D4 map language) |
| **Journal / quests** | Codex panel text + searchable dialog | Data dump typography, no hierarchy between quests | Witcher-3 reading surface: quest title typography, active-quest emphasis, filters as tabs, illustration (key art / NPC portrait) per entry |
| **Dialogue / chat** | Bubbles (grained GM / vellum player) | GM is a wall of same-weight prose; no faces | Speaker portraits beside GM beats when a codex NPC speaks; skill-check moments already interrupt as dice — keep; relationship chips on companion lines |
| **Dialogs (shop, saves, forge)** | AcceptDialogs with ItemLists | OS-dialog energy; instant pop-in | Shared ceremony: content fades/slides in, framed headers, polished buttons — every window uses the same entrance |
| **Skill tree** | Does not exist (level-up ceremony picks features) | — | Organic constellation tree (pan/zoom, curved glowing connections, monumental milestone nodes). New system — designed below, built in its own phase |

## 2. Design language (the reusable components)

All procedural, all palette-driven (three worlds re-tint everything — this is
already our super-power; no static assets to redraw).

- **Surfaces**: `forged` slabs (buttons), `ornate_frame` (windows/panels),
  `grain` parchment (reading surfaces), **new `socket`** (carved inset well
  for equipment), **new `glow`** (radial halo — rarity, focus, milestones).
- **Motion** (`Ui.polish`, `Ui.reveal`, `Ui.breathe` — all respect
  reduce_motion):
  - *polish(root)*: every Button gains hover-lift (scale 1.04, 0.12s ease-out)
    and press-dip (0.96); one call per screen.
  - *reveal(control, delay)*: fade + 12px rise on entry; stagger children for
    menu/dialog ceremony.
  - *breathe(control)*: 3s luminance sine for monumental elements only
    (title, milestone nodes). One per screen, max.
- **Feedback**: rarity halo behind item cards; board impact flash + rising
  damage number; audio hooks route through existing Sfx (tick/thud pending in
  make_sfx backlog).
- **Tooltips**: framed panel via `_make_custom_tooltip` — never the OS default.
  Item tooltips carry a **comparison block** vs the equipped piece (▲/▼).
- **Typography**: display serif tracked caps for titles/section heads (done);
  body sans 15; hint 13. Numbers that matter get size 19+.

## 3. Phases

| Phase | Scope | Status |
|---|---|---|
| **U0 Design system (MDL)** | tokens, surfaces, motion vocabulary, component library (Card/Socket/Tooltip/Header/Gauge/Portrait), gallery page — docs/DesignSystem.md is the contract | ✅ |
| **U1 Apply to Inventory + polish sweep** | inventory-as-object (cards not cells, capacity strap, doll around portrait, comparison tooltips, context menu, inspection), menu/game polish calls | 🔲 next |
| **U2 Combat feel** | initiative portrait chips, action bar icons, token slide tweens, damage numbers, impact flash | 🔲 |
| **U3 Living map** | pan/zoom camera, fog-of-war, pulsing quest/you-are-here markers | 🔲 |
| **U4 Journal & dialogue** | quest typography + filters + illustrations; GM speaker portraits; relationship chips | 🔲 |
| **U5 Skill tree** | constellation progression tree (pan/zoom, curved connections, glow paths); feeds from class features/feats data | 🔲 |
| **U6 Character screen** | full-screen sheet: doll integration, collapsible groups; 3D turntable exploration | 🔲 |

Mockups: see the published design-direction artifact (wireframes for U1–U5).

Anti-goals (rejected): visible GridContainers anywhere player-facing; OS
tooltips; instant pop-in dialogs; empty-slot placeholder boxes; uniform
font-weight walls of text.
